import Observation
import UserNotifications

/// 사용자의 알림 사용 의사(reminderEnabled)와 iOS 알림 권한을 합친 실제 상태
enum ReminderAvailability: Equatable {
    /// 사용자가 정리 알림을 끔
    case off
    /// 켜져 있고 iOS 권한도 있음. 실제로 알림이 간다.
    case active
    /// 켜져 있지만 아직 iOS 권한을 묻지 않음
    case needsPermission
    /// 켜져 있지만 iOS 설정에서 거부됨. 알림이 가지 않는다.
    case blockedBySystem
    /// 권한을 아직 확인하지 못함 (앱 시작 직후). 화면을 막지 않고 안내만 미룬다.
    case unknown

    static func resolve(enabled: Bool, authorization: UNAuthorizationStatus?) -> ReminderAvailability {
        guard enabled else { return .off }
        guard let authorization else { return .unknown }
        switch authorization {
        case .authorized, .provisional, .ephemeral: return .active
        case .notDetermined: return .needsPermission
        case .denied: return .blockedBySystem
        @unknown default: return .blockedBySystem
        }
    }
}

/// iOS 알림 권한 상태. 앱이 활성화될 때마다 다시 확인한다.
@MainActor
@Observable
final class NotificationPermission {
    static let shared = NotificationPermission()

    /// nil이면 아직 확인 전
    private(set) var authorization: UNAuthorizationStatus?

    func refresh() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func availability(enabled: Bool) -> ReminderAvailability {
        .resolve(enabled: enabled, authorization: authorization)
    }
}
