import Foundation

/// 스택에 보여줄 장소 문구. 우선순위: 행정구역 이름 → 변환 진행 상태 → 위치 기록 실패 안내
enum PlaceDisplay: Equatable {
    case place(String)
    case resolving
    case unresolved
    case lowAccuracy
    case unavailable(String)

    var text: String {
        switch self {
        case .place(let name): name
        case .resolving: "장소 확인 중"
        case .unresolved: "위치는 저장됨 · 장소 확인 불가"
        case .lowAccuracy: "위치 정확도 낮음"
        case .unavailable(let reason): reason
        }
    }

    /// 좌표는 있는데 변환만 실패한 경우에만 다시 시도할 수 있다.
    var canRetry: Bool { self == .unresolved }
}

extension Stack {
    /// 위치를 붙이는 중일 수 있는 시간. 이 시간이 지나도 결과가 없으면 실패로 본다.
    static let locationCaptureGracePeriod: TimeInterval = 10

    var placeDisplay: PlaceDisplay {
        switch locationStatus {
        case .disabled:
            return .unavailable("위치 기록 꺼짐")
        case .removed:
            return .unavailable("위치 삭제됨")
        case .notRequested where Date.now.timeIntervalSince(createdAt) < Self.locationCaptureGracePeriod:
            return .resolving
        case .notRequested, .unauthorized, .failed, .timedOut:
            return .unavailable("위치 확인 불가")
        case .captured:
            break
        }

        if let placeLabel {
            return .place(placeLabel)
        }
        guard hasCoordinate else { return .unavailable("위치 확인 불가") }
        guard let accuracy = horizontalAccuracy, accuracy >= 0, accuracy <= PlaceLabelFormatter.maxAccuracyForLabel else {
            return .lowAccuracy
        }
        return placeLookupAttempts >= PlaceLabelFormatter.maxLookupAttempts ? .unresolved : .resolving
    }
}
