import Foundation

/// 역지오코딩 결과 중 행정구역 표시에 쓰는 값만 추린 것
struct PlaceComponents: Equatable {
    var administrativeArea: String?
    var subAdministrativeArea: String?
    var locality: String?
    var subLocality: String?
    /// iOS 26 MapKit의 전체 주소. 예: "대한민국 서울특별시 성동구 아차산로 104, 04782"
    var fullAddress: String?
}

/// 좌표 정확도에 맞춰 확인된 행정구역까지만 문구로 만든다. 상호명·도로명은 쓰지 않는다.
enum PlaceLabelFormatter {
    /// 형식이 바뀌면 올린다. 이전 버전 문구는 다시 변환해 교체한다.
    static let version = 1
    /// 이보다 부정확하면 장소명을 붙이지 않는다.
    static let maxAccuracyForLabel: Double = 500
    /// 이보다 부정확하면 동 단위는 빼고 시·구까지만 표시한다.
    static let maxAccuracyForNeighborhood: Double = 100
    /// 변환 실패를 재시도하는 최대 횟수
    static let maxLookupAttempts = 3

    static func label(for components: PlaceComponents, accuracy: Double) -> String? {
        guard accuracy >= 0, accuracy <= maxAccuracyForLabel else { return nil }

        // Core Location은 한국 주소에 구(區)를 주지 않으므로, 전체 주소가 있으면 거기서 시·도·구·군을 읽는다.
        var parts = koreanAdministrativeUnits(in: components.fullAddress)
        if parts.isEmpty {
            parts = [components.administrativeArea, components.subAdministrativeArea, components.locality]
                .compactMap(nonEmpty)
        }
        if accuracy <= maxAccuracyForNeighborhood, let neighborhood = nonEmpty(components.subLocality) {
            parts.append(neighborhood)
        }

        var unique: [String] = []
        for part in parts where !unique.contains(part) {
            unique.append(part)
        }
        return unique.isEmpty ? nil : unique.joined(separator: " ")
    }

    /// "제주시청, 대한민국 제주특별자치도 제주시 이도이동 …" → ["제주특별자치도", "제주시"]
    static func koreanAdministrativeUnits(in fullAddress: String?) -> [String] {
        guard let fullAddress, let country = fullAddress.range(of: "대한민국") else { return [] }
        var units: [String] = []
        for token in fullAddress[country.upperBound...].split(whereSeparator: { $0 == " " || $0 == "," }) {
            let unit = String(token)
            guard isAdministrativeUnit(unit) else { break }
            units.append(unit)
        }
        return units
    }

    private static func isAdministrativeUnit(_ token: String) -> Bool {
        token.count >= 2
            && !token.contains(where: \.isNumber)
            && ["시", "도", "군", "구"].contains(where: token.hasSuffix)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
