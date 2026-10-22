import Foundation
import SwiftData

enum StackStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case discarded
}

enum CaptureSource: String, Codable {
    /// Back Tap, 단축어, 잠금화면 컨트롤 등 App Intent 경유 실행
    case appIntent
    /// 앱 안에서 직접 추가
    case inApp
    /// 백업 파일에서 가져옴
    case imported
}

enum LocationStatus: String, Codable {
    case notRequested
    case disabled
    case unauthorized
    case captured
    case failed
    case timedOut
    case removed

    var label: String {
        switch self {
        case .notRequested: "위치 확인 전"
        case .disabled: "위치 기록 꺼짐"
        case .unauthorized: "위치 권한 없음"
        case .captured: "위치 저장됨"
        case .failed: "위치 확인 실패"
        case .timedOut: "위치 확인 시간 초과"
        case .removed: "위치 삭제됨"
        }
    }
}

/// 결제 순간에 남기는 지출 흔적. 결제 증명이 아니라 사용자가 수동으로 남긴 기록이다 (BR-01).
@Model
final class Stack {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var captureSourceRaw: String
    var statusRaw: String
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var locationStatusRaw: String
    var placeLabel: String?
    var completedAt: Date?
    var transactionId: UUID?
    var discardedAt: Date?
    /// 직전 스택과 너무 가깝게 생성된 경우 표시만 한다. 자동으로 지우지 않는다 (BR-10).
    var isPossibleDuplicate: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        captureSource: CaptureSource,
        status: StackStatus = .pending,
        locationStatus: LocationStatus = .notRequested,
        isPossibleDuplicate: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captureSourceRaw = captureSource.rawValue
        self.statusRaw = status.rawValue
        self.locationStatusRaw = locationStatus.rawValue
        self.isPossibleDuplicate = isPossibleDuplicate
    }

    var status: StackStatus {
        get { StackStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var captureSource: CaptureSource {
        get { CaptureSource(rawValue: captureSourceRaw) ?? .appIntent }
        set { captureSourceRaw = newValue.rawValue }
    }

    var locationStatus: LocationStatus {
        get { LocationStatus(rawValue: locationStatusRaw) ?? .notRequested }
        set { locationStatusRaw = newValue.rawValue }
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    func clearLocation() {
        latitude = nil
        longitude = nil
        horizontalAccuracy = nil
        placeLabel = nil
        locationStatus = .removed
    }
}
