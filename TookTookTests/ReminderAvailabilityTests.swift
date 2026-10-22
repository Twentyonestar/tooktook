import Testing
import UserNotifications
@testable import TookTook

struct ReminderAvailabilityTests {
    @Test(arguments: [
        (UNAuthorizationStatus.authorized, ReminderAvailability.active),
        (.provisional, .active),
        (.ephemeral, .active),
        (.notDetermined, .needsPermission),
        (.denied, .blockedBySystem),
    ])
    func enabledPreferenceFollowsSystemPermission(status: UNAuthorizationStatus, expected: ReminderAvailability) {
        #expect(ReminderAvailability.resolve(enabled: true, authorization: status) == expected)
    }

    @Test func userOffWinsOverAnyPermission() {
        for status: UNAuthorizationStatus in [.authorized, .denied, .notDetermined] {
            #expect(ReminderAvailability.resolve(enabled: false, authorization: status) == .off)
        }
    }

    @Test func unknownUntilChecked() {
        // 앱 시작 직후 권한 확인 전에는 거부 안내도, 정상 안내도 확정하지 않는다
        #expect(ReminderAvailability.resolve(enabled: true, authorization: nil) == .unknown)
    }

    @Test func deniedPermissionKeepsUserChoiceSeparate() {
        // 시스템에서 거부돼도 사용자의 '켜짐' 의사는 바뀌지 않고, 실제 상태만 차단으로 표시된다
        let enabled = true
        #expect(ReminderAvailability.resolve(enabled: enabled, authorization: .denied) == .blockedBySystem)
        #expect(enabled)
    }

    @Test func schedulingOnlyWithPermission() {
        #expect(ReminderScheduler.canSchedule(authorization: .authorized))
        #expect(ReminderScheduler.canSchedule(authorization: .provisional))
        #expect(!ReminderScheduler.canSchedule(authorization: .denied))
        #expect(!ReminderScheduler.canSchedule(authorization: .notDetermined))
    }

    @Test func regrantedPermissionRestoresSavedTime() {
        // 권한이 돌아오면 저장해 둔 시각 그대로 다시 예약된다
        let savedMinutes = 21 * 60 + 30
        #expect(ReminderScheduler.canSchedule(authorization: .authorized))
        let plan = ReminderScheduler.plan(pendingCount: 2, enabled: true, minutes: savedMinutes, now: .now)
        let calendar = Calendar.current
        #expect(plan.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 21 && calendar.component(.minute, from: $0.fireDate) == 30 })
    }
}
