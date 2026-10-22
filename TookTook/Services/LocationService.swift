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

/// 스택 저장 이후에 위치를 덧붙인다 (BR-03). 실패해도 스택은 그대로 남는다.
@MainActor
enum LocationEnricher {
    static let captureTimeout: Duration = .seconds(4)
    /// 이보다 부정확하면 주소를 붙이지 않는다.
    static let maxAccuracyForLabel: Double = 500
    /// 이보다 부정확하면 동 단위까지만 표시한다.
    static let maxAccuracyForStreet: Double = 100

    static func attachLocation(to stack: Stack, in context: ModelContext) async {
        let service = LocationService.shared
        if !Preferences.locationCaptureEnabled {
            stack.locationStatus = .disabled
        } else if !service.isAuthorized {
            stack.locationStatus = .unauthorized
        } else {
            switch await service.requestOneShot(timeout: captureTimeout) {
            case .located(let location):
                stack.latitude = location.coordinate.latitude
                stack.longitude = location.coordinate.longitude
                stack.horizontalAccuracy = location.horizontalAccuracy
                stack.locationStatus = .captured
            case .failed:
                stack.locationStatus = .failed
            case .timedOut:
                stack.locationStatus = .timedOut
            }
        }
        try? context.save()
    }

    /// 좌표는 있지만 주소가 없는 스택에 대략적인 지역명을 붙인다. 상호명은 추정하지 않는다.
    static func resolvePlaceLabels(in context: ModelContext) async {
        let captured = LocationStatus.captured.rawValue
        let descriptor = FetchDescriptor<Stack>(
            predicate: #Predicate { $0.locationStatusRaw == captured && $0.placeLabel == nil }
        )
        guard let stacks = try? context.fetch(descriptor), !stacks.isEmpty else { return }

        let geocoder = CLGeocoder()
        for stack in stacks {
            guard let latitude = stack.latitude, let longitude = stack.longitude,
                  let accuracy = stack.horizontalAccuracy, accuracy >= 0, accuracy <= maxAccuracyForLabel
            else { continue }

            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { continue }

            var parts = [placemark.subLocality ?? placemark.locality]
            if accuracy <= maxAccuracyForStreet {
                parts.append(placemark.thoroughfare)
            }
            let label = parts.compactMap { $0 }.joined(separator: " ")
            if !label.isEmpty, stack.locationStatus == .captured {
                stack.placeLabel = label
            }
        }
        try? context.save()
    }
}
