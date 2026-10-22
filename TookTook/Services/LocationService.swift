import CoreLocation
import Observation
import SwiftData

enum LocationOutcome {
    case located(CLLocation)
    case failed
    case timedOut
}

/// 한 번만 위치를 요청하는 얇은 래퍼. 권한 요청은 설정 화면에서만 한다.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var authorizationStatus: CLAuthorizationStatus
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var continuation: CheckedContinuation<LocationOutcome, Never>?
    @ObservationIgnored private var requestID = UUID()

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShot(timeout: Duration) async -> LocationOutcome {
        guard continuation == nil else { return .failed }
        return await withCheckedContinuation { continuation in
            let id = UUID()
            self.requestID = id
            self.continuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.requestID == id else { return }
                self.finish(.timedOut)
            }
        }
    }

    private func finish(_ outcome: LocationOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.located(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failed) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }
}

/// 위치 수집 시점의 조건. 테스트에서 권한·타임아웃 상황을 재현하려고 분리했다.
enum LocationCaptureResult {
    case disabled
    case unauthorized
    case attempted(LocationOutcome)
}

/// 스택 저장 이후에 위치를 덧붙인다 (BR-03). 실패해도 스택은 그대로 남는다.
@MainActor
enum LocationEnricher {
    static let captureTimeout: Duration = .seconds(4)
    /// 한 번에 보내는 주소 변환 요청 상한. Apple 지오코딩 사용량 제한을 넘지 않기 위함.
    static let maxGeocodeRequestsPerRun = 20

    /// 변환 중에 들어온 요청. 버리지 않고 현재 실행이 끝난 뒤 한 번 더 돈다.
    private static var rerunRequested: Set<ObjectIdentifier> = []

    static func attachLocation(to stack: Stack, in context: ModelContext) async {
        let service = LocationService.shared
        let result: LocationCaptureResult
        if !Preferences.locationCaptureEnabled {
            result = .disabled
        } else if !service.isAuthorized {
            result = .unauthorized
        } else {
            result = .attempted(await service.requestOneShot(timeout: captureTimeout))
        }
        record(result, on: stack)
        try? context.save()
    }

    static func record(_ result: LocationCaptureResult, on stack: Stack) {
        switch result {
        case .disabled:
            stack.locationStatus = .disabled
        case .unauthorized:
            stack.locationStatus = .unauthorized
        case .attempted(.located(let location)):
            stack.latitude = location.coordinate.latitude
            stack.longitude = location.coordinate.longitude
            stack.horizontalAccuracy = location.horizontalAccuracy
            stack.locationStatus = .captured
        case .attempted(.failed):
            stack.locationStatus = .failed
        case .attempted(.timedOut):
            stack.locationStatus = .timedOut
        }
    }

    /// 한 번의 변환 실행(재실행 포함) 동안 공유하는 상태
    private struct ResolveRun {
        /// 이번 실행에서 이미 처리한 스택. 재실행 때 같은 스택의 실패 횟수를 또 올리지 않는다.
        var handled: Set<UUID> = []
        /// 좌표(약 10m 격자)별 결과. nil 값은 이번 실행에서 실패한 좌표라 다시 요청하지 않는다.
        var results: [String: PlaceComponents?] = [:]
        var requests = 0
    }

    private static var runs: [ObjectIdentifier: ResolveRun] = [:]

    /// 좌표는 있지만 장소명이 없거나 예전 형식인 스택에 행정구역 이름을 붙인다.
    /// 실행 중에 들어온 요청은 버리지 않고, 현재 실행이 끝나면 새 대상만 이어서 처리한다.
    /// 스택마다 저장해 중간에 끊겨도 진행분은 남고, 실패해도 좌표는 그대로 둔다.
    static func resolvePlaceLabels(
        in context: ModelContext,
        geocoder: PlaceGeocoding = SystemPlaceGeocoder()
    ) async {
        let contextID = ObjectIdentifier(context)
        guard runs[contextID] == nil else {
            rerunRequested.insert(contextID)
            return
        }
        runs[contextID] = ResolveRun()
        defer { runs[contextID] = nil }

        repeat {
            rerunRequested.remove(contextID)
            await resolvePendingStacks(in: context, contextID: contextID, geocoder: geocoder)
        } while rerunRequested.contains(contextID)
    }

    private static func resolvePendingStacks(
        in context: ModelContext,
        contextID: ObjectIdentifier,
        geocoder: PlaceGeocoding
    ) async {
        let version = PlaceLabelFormatter.version
        let descriptor = FetchDescriptor<Stack>(
            predicate: Stack.needsPlaceResolution,
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let stacks = try? context.fetch(descriptor), !stacks.isEmpty else { return }

        for stack in stacks {
            guard runs[contextID]?.handled.contains(stack.id) == false,
                  let latitude = stack.latitude, let longitude = stack.longitude,
                  let accuracy = stack.horizontalAccuracy, accuracy >= 0,
                  accuracy <= PlaceLabelFormatter.maxAccuracyForLabel
            else { continue }

            let key = coordinateKey(latitude: latitude, longitude: longitude)
            let components: PlaceComponents?
            if let cached = runs[contextID]?.results[key] {
                components = cached
            } else {
                guard (runs[contextID]?.requests ?? 0) < maxGeocodeRequestsPerRun else { break }
                runs[contextID]?.requests += 1
                do {
                    components = try await geocoder.components(for: CLLocation(latitude: latitude, longitude: longitude))
                } catch {
                    // 작업 취소는 변환 실패가 아니다. 실패 횟수를 올리지 않고 다음 실행에 맡긴다.
                    if Task.isCancelled || error is CancellationError { return }
                    components = nil
                }
                runs[contextID]?.results[key] = .some(components)
            }
            runs[contextID]?.handled.insert(stack.id)

            // 기다리는 동안 위치가 삭제됐으면 건드리지 않는다.
            guard stack.locationStatus == .captured else { continue }
            if let components, let label = PlaceLabelFormatter.label(for: components, accuracy: accuracy) {
                stack.placeLabel = label
                stack.placeLabelVersion = version
            } else {
                stack.placeLookupAttempts += 1
            }
            try? context.save()
        }
    }

    private static func coordinateKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// 사용자가 '장소 다시 확인'을 눌렀을 때. 저장된 과거 좌표로 다시 변환하며 현재 위치는 쓰지 않는다.
    static func retryPlaceLookup(
        for stack: Stack,
        in context: ModelContext,
        geocoder: PlaceGeocoding = SystemPlaceGeocoder()
    ) async {
        stack.placeLookupAttempts = 0
        try? context.save()
        // 실행 중이라면 이 스택과 좌표를 이번 실행의 처리 기록에서 빼서 다시 요청되게 한다.
        let contextID = ObjectIdentifier(context)
        runs[contextID]?.handled.remove(stack.id)
        if let latitude = stack.latitude, let longitude = stack.longitude {
            runs[contextID]?.results[coordinateKey(latitude: latitude, longitude: longitude)] = nil
        }
        await resolvePlaceLabels(in: context, geocoder: geocoder)
    }
}
