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
}

/// 앱 코드는 별칭으로 현재 스키마 버전의 모델을 쓴다. 새 버전을 추가하면 별칭을 옮긴다.
typealias Stack = SchemaV2.Stack

extension SchemaV2 {
    /// 결제 순간에 남기는 지출 흔적. 결제 증명이 아니라 사용자가 수동으로 남긴 기록이다 (BR-01).
    @Model
    final class Stack {
        // CloudKit 호환: unique 없음, 필수 속성마다 기본값. 기본값은 스키마 요건일 뿐 init이 항상 실제 값을 넣는다.
        // id 중복은 StackStore와 DuplicateIDResolver가 앱 수준에서 막는다.
        var id: UUID = UUID()
        var createdAt: Date = Date.distantPast
        var captureSourceRaw: String = "appIntent"
        var statusRaw: String = "pending"
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracy: Double?
        var locationStatusRaw: String = "notRequested"
        var placeLabel: String?
        var completedAt: Date?
        var transactionId: UUID?
        var discardedAt: Date?
        /// 직전 스택과 너무 가깝게 생성된 경우 표시만 한다. 자동으로 지우지 않는다 (BR-10).
        var isPossibleDuplicate: Bool = false
        /// 주소 변환 실패 횟수. PlaceLabelFormatter.maxLookupAttempts에 닿으면 자동 재시도를 멈춘다.
        var placeLookupAttempts: Int = 0
        /// placeLabel을 만든 PlaceLabelFormatter.version. 낮으면 새 형식으로 다시 변환한다.
        var placeLabelVersion: Int = 0

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
}
