import Foundation
import Testing
@testable import TookTook

struct ReminderPreferencesTests {
    /// 테스트마다 분리된 저장소. 같은 suiteName으로 다시 열면 앱 재실행과 같다.
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "tooktook.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func defaultsToTenPmAndEnabled() {
        let (defaults, _) = freshDefaults()
        #expect(Preferences.reminderMinutes(in: defaults) == 22 * 60)
        #expect(Preferences.reminderEnabled(in: defaults))

        let seoul = calendar("Asia/Seoul")
        let shown = Preferences.reminderDate(fromMinutes: Preferences.reminderMinutes(in: defaults), calendar: seoul, on: date(seoul, 2026, 10, 23, 9))
        #expect(seoul.component(.hour, from: shown) == 22)
        #expect(seoul.component(.minute, from: shown) == 0)
    }

    @Test func pickedTimeIsStoredAndSurvivesRelaunch() {
        let (defaults, suite) = freshDefaults()
        let seoul = calendar("Asia/Seoul")
        let picked = date(seoul, 2026, 10, 23, 21, 30)

        defaults.set(Preferences.reminderMinutes(from: picked, calendar: seoul), forKey: PrefKey.reminderMinutes)

        let reopened = UserDefaults(suiteName: suite)!
        #expect(Preferences.reminderMinutes(in: reopened) == 21 * 60 + 30)
    }

    @Test(arguments: [(0, 0), (0, 30), (23, 59), (12, 0)])
    func timesAroundMidnightRoundTrip(hour: Int, minute: Int) {
        let seoul = calendar("Asia/Seoul")
        let minutes = hour * 60 + minute
        let shown = Preferences.reminderDate(fromMinutes: minutes, calendar: seoul, on: date(seoul, 2026, 10, 23, 15))
        #expect(Preferences.reminderMinutes(from: shown, calendar: seoul) == minutes)
    }

    @Test func turningRemindersOffSchedulesNothing() {
        let (defaults, _) = freshDefaults()
        defaults.set(false, forKey: PrefKey.reminderEnabled)

        let plan = ReminderScheduler.plan(
            pendingCount: 3,
            enabled: Preferences.reminderEnabled(in: defaults),
            minutes: Preferences.reminderMinutes(in: defaults),
            now: .now
        )
        #expect(plan.isEmpty)
    }

    @Test func changingTimeReschedulesWithSameIdentifiers() {
        let seoul = calendar("Asia/Seoul")
        let now = date(seoul, 2026, 10, 23, 12)
        let before = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 22 * 60, now: now, calendar: seoul)
        let after = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 19 * 60 + 15, now: now, calendar: seoul)

        // 같은 식별자로 다시 예약하므로 이전 알림은 교체된다
        #expect(before.map(\.identifier) == after.map(\.identifier))
        #expect(after.first?.fireDate == date(seoul, 2026, 10, 23, 19, 15))
        #expect(after.allSatisfy { seoul.component(.hour, from: $0.fireDate) == 19 && seoul.component(.minute, from: $0.fireDate) == 15 })
    }

    @Test func midnightChoiceFiresAtNextMidnight() {
        let seoul = calendar("Asia/Seoul")
        let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 0, now: date(seoul, 2026, 10, 23, 23, 30), calendar: seoul)
        #expect(plan.first?.fireDate == date(seoul, 2026, 10, 24, 0, 0))
    }

    @Test func justBeforeMidnightFiresToday() {
        let seoul = calendar("Asia/Seoul")
        let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 23 * 60 + 59, now: date(seoul, 2026, 10, 23, 23, 58), calendar: seoul)
        #expect(plan.first?.fireDate == date(seoul, 2026, 10, 23, 23, 59))
    }

    @Test func sameChoiceFollowsLocalTimeAfterTimeZoneChange() {
        let minutes = 21 * 60 + 45
        for zone in ["Asia/Seoul", "America/Los_Angeles", "Europe/London"] {
            let local = calendar(zone)
            let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: minutes, now: date(local, 2026, 10, 23, 8), calendar: local)
            #expect(local.component(.hour, from: plan[0].fireDate) == 21, "\(zone)")
            #expect(local.component(.minute, from: plan[0].fireDate) == 45, "\(zone)")
        }
    }

    @Test func nothingScheduledWithoutPendingStacks() {
        #expect(ReminderScheduler.plan(pendingCount: 0, enabled: true, minutes: 20 * 60, now: .now).isEmpty)
    }
}
