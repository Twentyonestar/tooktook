import CoreLocation
import MapKit

@MainActor
protocol PlaceGeocoding {
    /// 결과가 없으면 nil, 네트워크 등 실패는 오류를 던진다.
    func components(for location: CLLocation) async throws -> PlaceComponents?
}

/// Apple 지도 서비스로만 변환한다. 자체 서버로 위치를 보내지 않는다.
struct SystemPlaceGeocoder: PlaceGeocoding {
    private static let locale = Locale(identifier: "ko_KR")

    /// 기본 인자로 쓸 수 있도록 격리하지 않는다.
    nonisolated init() {}

    func components(for location: CLLocation) async throws -> PlaceComponents? {
        if #available(iOS 26.0, *) {
            return try await mapKitComponents(for: location)
        }
        return try await coreLocationComponents(for: location)
    }

    /// iOS 26+: 전체 주소에 구(區)가 포함된다.
    @available(iOS 26.0, *)
    private func mapKitComponents(for location: CLLocation) async throws -> PlaceComponents? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Self.locale
        guard let item = try await request.mapItems.first else { return nil }
        var components = Self.components(from: Self.legacyPlacemark(of: item))
        components.fullAddress = item.address?.fullAddress
        return components
    }

    /// iOS 17~25: CLGeocoder. 한국 주소는 시·도와 동까지만 온다.
    private func coreLocationComponents(for location: CLLocation) async throws -> PlaceComponents? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Self.locale)
        return placemarks.first.map(Self.components(from:))
    }

    /// iOS 26에서 동 이름(subLocality)은 아직 MKMapItem.placemark에만 있다.
    /// 배포 대상(iOS 17) 기준 함수로 두어 deprecated 경고 없이 읽는다.
    private static func legacyPlacemark(of item: MKMapItem) -> CLPlacemark {
        item.placemark
    }

    private static func components(from placemark: CLPlacemark) -> PlaceComponents {
        PlaceComponents(
            administrativeArea: placemark.administrativeArea,
            subAdministrativeArea: placemark.subAdministrativeArea,
            locality: placemark.locality,
            subLocality: placemark.subLocality
        )
    }
}
