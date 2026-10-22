import Foundation
import UserNotifications

/// 정리 알림 예약. 첫날 알림에는 정확한 건수를 쓰고, 앱이 실행되지 않아 갱신할 수 없는
/// 이후 날짜에는 건수 없는 폴백 문구를 예약해 둔다 (FR-05).
enum ReminderScheduler {
    static let identifierPrefix = "stack-reminder-"
    static let fallbackDays = 7
    static let destinationKey = "destination"
    static let inboxDestination = "inbox"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func refresh(pendingCount: Int, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<fallbackDays).map { "\(identifierPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard Preferences.reminderEnabled, pendingCount > 0 else { return }

        let minutes = Preferences.reminderMinutes
        // 사용자의 로컬 시간대를 따른다 (BR-07).
        let calendar = Calendar.current
        guard let firstFire = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: minutes / 60, minute: minutes % 60),
            matchingPolicy: .nextTime
        ) else { return }

        for offset in 0..<fallbackDays {
            guard let fireDate = calendar.date(byAdding: .day, value: offset, to: firstFire) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "오늘의 스택 정리"
            content.body = offset == 0
                ? "정리하지 않은 스택이 \(pendingCount)개 있어요. 지금 정리해 볼까요?"
                : "아직 정리하지 않은 스택이 있을 수 있어요."
            content.sound = .default
            content.userInfo = [destinationKey: inboxDestination]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifiers[offset], content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
