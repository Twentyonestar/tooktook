import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import TookTook

/// 실제 서버 응답(2026-10-23 Mac에서 측정)을 본뜬 값
private enum Sample {
    static let guroMapKit = PlaceComponents(
        administrativeArea: "서울특별시", locality: "서울특별시", subLocality: "구로동",
        fullAddress: "대한민국 서울특별시 구로구 구로동 479-20, 08281"
    )
    static let seongsuMapKit = PlaceComponents(
        administrativeArea: "서울특별시", locality: "서울특별시", subLocality: "성수동2가",
        fullAddress: "대한민국 서울특별시 성동구 아차산로 104, 04782"
    )
    static let jeongjaMapKit = PlaceComponents(
        administrativeArea: "경기도", locality: "성남시", subLocality: "정자동",
        fullAddress: "대한민국 경기도 성남시 분당구 성남대로 333, 13558"
    )
    static let jejuWithPOI = PlaceComponents(
        administrativeArea: "제주특별자치도", locality: "제주시", subLocality: "이도이동",
        fullAddress: "제주시청, 대한민국 제주특별자치도 제주시 이도이동 1055-2, 63208"
    )
    static let yangpyeong = PlaceComponents(
        administrativeArea: "경기도", subAdministrativeArea: "양평군", subLocality: "양평읍",
        fullAddress: "대한민국 경기도 양평군 양평읍 군청앞길 2, 12554"
    )
    /// iOS 17~25 CLGeocoder: 구가 없다
    static let guroCoreLocation = PlaceComponents(
        administrativeArea: "서울특별시", locality: "서울특별시", subLocality: "구로동"
    )
}

/// 호출 횟수를 세는 가짜 지오코더
@MainActor
final class FakeGeocoder: PlaceGeocoding {
    enum Response {
        case success(PlaceComponents)
        case noResult
        case failure
    }

    var response: Response
    private(set) var requestCount = 0

    init(_ response: Response) {
        self.response = response
    }

    func components(for location: CLLocation) async throws -> PlaceComponents? {
        requestCount += 1
        switch response {
        case .success(let components): return components
        case .noResult: return nil
        case .failure: throw URLError(.notConnectedToInternet)
        }
    }
}

struct PlaceLabelFormatterTests {
    @Test(arguments: [
        (Sample.guroMapKit, "서울특별시 구로구 구로동"),
        (Sample.seongsuMapKit, "서울특별시 성동구 성수동2가"),
        (Sample.jeongjaMapKit, "경기도 성남시 분당구 정자동"),
        (Sample.jejuWithPOI, "제주특별자치도 제주시 이도이동"),
        (Sample.yangpyeong, "경기도 양평군 양평읍"),
        (Sample.guroCoreLocation, "서울특별시 구로동"),
    ])
    func administrativeLabelWithinHundredMeters(components: PlaceComponents, expected: String) {
        #expect(PlaceLabelFormatter.label(for: components, accuracy: 15) == expected)
    }

    @Test func dropsNeighborhoodBetweenHundredAndFiveHundredMeters() {
        #expect(PlaceLabelFormatter.label(for: Sample.seongsuMapKit, accuracy: 250) == "서울특별시 성동구")
        #expect(PlaceLabelFormatter.label(for: Sample.guroCoreLocation, accuracy: 250) == "서울특별시")
    }

    @Test func noLabelBeyondFiveHundredMeters() {
        #expect(PlaceLabelFormatter.label(for: Sample.seongsuMapKit, accuracy: 800) == nil)
        #expect(PlaceLabelFormatter.label(for: Sample.seongsuMapKit, accuracy: -1) == nil)
    }

    @Test func neverUsesStreetOrBusinessNames() {
        let label = PlaceLabelFormatter.label(for: Sample.jejuWithPOI, accuracy: 10) ?? ""
        #expect(!label.contains("제주시청"))
        #expect(!label.contains("아차산로"))
        #expect(!label.contains("1055"))
    }

    @Test func emptyComponentsGiveNoLabel() {
        #expect(PlaceLabelFormatter.label(for: PlaceComponents(), accuracy: 10) == nil)
    }
}

@MainActor
struct PlaceResolutionTests {
    private func capturedStack(in t: TestStore, latitude: Double = 37.5446, longitude: Double = 127.0557, accuracy: Double = 15) throws -> Stack {
        let stack = try t.store.createStack(source: .appIntent, at: Date(timeIntervalSince1970: 1_800_000_000))
        LocationEnricher.record(
            .attempted(.located(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now
            ))),
            on: stack
        )
        try t.context.save()
        return stack
    }

    @Test func coordinateAndGeocodeSuccess() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        #expect(stack.placeDisplay == .resolving)

        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.success(Sample.seongsuMapKit)))

        #expect(stack.placeLabel == "서울특별시 성동구 성수동2가")
        #expect(stack.placeLabelVersion == PlaceLabelFormatter.version)
        #expect(stack.placeDisplay == .place("서울특별시 성동구 성수동2가"))
    }

    @Test func geocodeFailureKeepsCoordinateAndRetriesUpToLimit() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        let geocoder = FakeGeocoder(.failure)

        for _ in 0..<PlaceLabelFormatter.maxLookupAttempts {
            await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: geocoder)
        }
        #expect(stack.latitude == 37.5446)
        #expect(stack.longitude == 127.0557)
        #expect(stack.placeLabel == nil)
        #expect(stack.placeDisplay == .unresolved)
        #expect(stack.placeDisplay.text == "위치는 저장됨 · 장소 확인 불가")

        // 한도에 닿으면 더 요청하지 않는다
        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: geocoder)
        #expect(geocoder.requestCount == PlaceLabelFormatter.maxLookupAttempts)
    }

    @Test func noResultCountsAsFailure() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.noResult))
        #expect(stack.placeLookupAttempts == 1)
        #expect(stack.placeDisplay == .resolving)
    }

    @Test func manualRetryResetsAttemptsAndUsesStoredCoordinate() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        stack.placeLookupAttempts = PlaceLabelFormatter.maxLookupAttempts
        #expect(stack.placeDisplay.canRetry)

        stack.placeLookupAttempts = 0
        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.success(Sample.seongsuMapKit)))

        #expect(stack.placeLabel == "서울특별시 성동구 성수동2가")
        #expect(stack.latitude == 37.5446)
    }

    @Test func mediumAccuracyStopsAtDistrict() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t, accuracy: 300)
        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.success(Sample.seongsuMapKit)))
        #expect(stack.placeLabel == "서울특별시 성동구")
    }

    @Test func lowAccuracySkipsGeocoding() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t, accuracy: 800)
        let geocoder = FakeGeocoder(.success(Sample.seongsuMapKit))

        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: geocoder)

        #expect(geocoder.requestCount == 0)
        #expect(stack.placeDisplay == .lowAccuracy)
        #expect(stack.hasCoordinate)
    }

    @Test func sameCoordinateIsRequestedOnce() async throws {
        let t = try TestStore()
        let first = try capturedStack(in: t)
        let second = try capturedStack(in: t, latitude: 37.54461, longitude: 127.05572)
        let third = try capturedStack(in: t, latitude: 37.4968, longitude: 126.8802)
        let geocoder = FakeGeocoder(.success(Sample.seongsuMapKit))

        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: geocoder)

        #expect(geocoder.requestCount == 2)
        #expect([first, second, third].allSatisfy { $0.placeLabel != nil })
    }

    @Test func oldFormatLabelIsUpgraded() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t, latitude: 37.4968, longitude: 126.8802)
        stack.placeLabel = "구로동 구로동"
        stack.placeLabelVersion = 0
        try t.context.save()
        #expect(stack.placeDisplay == .place("구로동 구로동"))

        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.success(Sample.guroMapKit)))

        #expect(stack.placeLabel == "서울특별시 구로구 구로동")
    }

    @Test func labelPersistsAcrossNewContext() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: FakeGeocoder(.success(Sample.seongsuMapKit)))

        // 앱 재실행처럼 같은 저장소에 새 컨텍스트로 접근
        let reopened = ModelContext(t.container)
        let id = stack.id
        let fetched = try #require(try reopened.fetch(FetchDescriptor<Stack>(predicate: #Predicate { $0.id == id })).first)
        #expect(fetched.placeLabel == "서울특별시 성동구 성수동2가")
        #expect(fetched.placeDisplay == .place("서울특별시 성동구 성수동2가"))
    }

    @Test func removedLocationIsNotResolved() async throws {
        let t = try TestStore()
        let stack = try capturedStack(in: t)
        stack.clearLocation()
        try t.context.save()
        let geocoder = FakeGeocoder(.success(Sample.seongsuMapKit))

        await LocationEnricher.resolvePlaceLabels(in: t.context, geocoder: geocoder)

        #expect(geocoder.requestCount == 0)
        #expect(stack.placeDisplay == .unavailable("위치 삭제됨"))
    }
}

@MainActor
struct LocationCaptureTests {
    private func oldStack(_ t: TestStore) throws -> Stack {
        // 위치 확인 유예 시간이 지난 스택
        try t.store.createStack(source: .appIntent, at: Date.now.addingTimeInterval(-60))
    }

    @Test func permissionDeniedKeepsStackWithoutCoordinate() throws {
        let t = try TestStore()
        let stack = try oldStack(t)
        LocationEnricher.record(.unauthorized, on: stack)

        #expect(stack.status == .pending)
        #expect(!stack.hasCoordinate)
        #expect(stack.placeDisplay == .unavailable("위치 확인 불가"))
    }

    @Test func timeoutKeepsStackWithoutCoordinate() throws {
        let t = try TestStore()
        let stack = try oldStack(t)
        LocationEnricher.record(.attempted(.timedOut), on: stack)

        #expect(stack.locationStatus == .timedOut)
        #expect(!stack.hasCoordinate)
        #expect(stack.placeDisplay == .unavailable("위치 확인 불가"))
    }

    @Test func disabledCaptureIsExplained() throws {
        let t = try TestStore()
        let stack = try oldStack(t)
        LocationEnricher.record(.disabled, on: stack)
        #expect(stack.placeDisplay == .unavailable("위치 기록 꺼짐"))
    }

    @Test func freshStackShowsResolvingWhileLocationIsPending() throws {
        let t = try TestStore()
        let stack = try t.store.createStack(source: .appIntent)
        #expect(stack.placeDisplay == .resolving)
    }
}
