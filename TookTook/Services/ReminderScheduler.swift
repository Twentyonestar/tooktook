import Foundation
import UserNotifications

/// 예약할 정리 알림 한 건
struct PlannedReminder: Equatable {
    let identifier: String
    let fireDate: Date
    let body: String
}

/// 정리 알림 예약. 첫 알림에는 정확한 건수를 쓰고, 앱이 실행되지 않아 갱신할 수 없는
/// 이후 날짜에는 건수 없는 폴백 문구를 예약해 둔다 (FR-05).
///
/// 트레이드오프: 매일 반복 알림 하나로 두면 건수를 넣을 수 없고, 모두 정리한 뒤에도
/// 앱이 갱신하기 전까지 오알림이 난다. 지금 방식은 스택 생성·정리 때마다 다시 예약하므로
/// 건수가 0이면 즉시 취소되지만, 앱과 단축어를 7일 넘게 전혀 실행하지 않으면 알림이 끊긴다.
/// 그 사이 새 스택도 생기지 않았다는 뜻이므로 누락의 비용이 작다고 판단했다.
enum ReminderScheduler {
    static let identifierPrefix = "stack-reminder-"
    static let fallbackDays = 7
    static let destinationKey = "destination"
    static let inboxDestination = "inbox"

    static var allIdentifiers: [String] {
        (0..<fallbackDays).map { "\(identifierPrefix)\($0)" }
    }

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// iOS 권한이 없으면 예약해도 전달되지 않으므로 예약하지 않는다.
    static func canSchedule(authorization: UNAuthorizationStatus) -> Bool {
        ReminderAvailability.resolve(enabled: true, authorization: authorization) == .active
    }

    /// 순수 계산. 시스템 상태를 건드리지 않으므로 테스트할 수 있다.
    /// 사용자의 로컬 시간대(calendar)를 따른다 (BR-07).
    static func plan(
        pendingCount: Int,
        enabled: Bool,
        minutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        guard enabled, pendingCount > 0 else { return [] }
        guard let firstFire = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: minutes / 60, minute: minutes % 60),
            matchingPolicy: .nextTime
        ) else { return [] }

        return (0..<fallbackDays).compactMap { offset in
            guard let fireDate = calendar.date(byAdding: .day, value: offset, to: firstFire) else { return nil }
            let body = offset == 0
                ? "정리하지 않은 스택이 \(pendingCount)개 있어요. 지금 정리해 볼까요?"
                : "아직 정리하지 않은 스택이 있을 수 있어요."
            return PlannedReminder(identifier: "\(identifierPrefix)\(offset)", fireDate: fireDate, body: body)
        }
    }

    /// 실패해도 오류를 던지지 않는다. 호출하는 쪽(스택 저장)의 성공과 분리하기 위함.
    static func refresh(pendingCount: Int, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
        // 권한을 다시 허용하면 앱 활성화 때 이 함수가 다시 불려 저장된 시각으로 복구된다.
        guard canSchedule(authorization: await center.notificationSettings().authorizationStatus) else { return }

        let calendar = Calendar.current
        let reminders = plan(
            pendingCount: pendingCount,
            enabled: Preferences.reminderEnabled,
            minutes: Preferences.reminderMinutes,
            now: now,
            calendar: calendar
        )
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "오늘의 스택 정리"
            content.body = reminder.body
            content.sound = .default
            content.userInfo = [destinationKey: inboxDestination]

            // 시간대 없이 벽시계 기준으로 예약해, 기기 시간대가 바뀌어도 현지 시각에 울리게 한다.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }
}
