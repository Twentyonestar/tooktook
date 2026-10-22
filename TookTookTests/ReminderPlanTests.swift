import Foundation
import Testing
@testable import TookTook

struct ReminderPlanTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func noRemindersWhenNothingPending() {
        let plan = ReminderScheduler.plan(pendingCount: 0, enabled: true, minutes: 22 * 60, now: .now)
        #expect(plan.isEmpty)
    }

    @Test func noRemindersWhenDisabled() {
        let plan = ReminderScheduler.plan(pendingCount: 3, enabled: false, minutes: 22 * 60, now: .now)
        #expect(plan.isEmpty)
    }

    @Test func firesTonightBeforeReminderTime() {
        let seoul = calendar("Asia/Seoul")
        let now = date(seoul, 2026, 10, 23, 21, 0)
        let plan = ReminderScheduler.plan(pendingCount: 2, enabled: true, minutes: 22 * 60, now: now, calendar: seoul)

        #expect(plan.count == ReminderScheduler.fallbackDays)
        #expect(plan[0].fireDate == date(seoul, 2026, 10, 23, 22, 0))
        #expect(plan[0].body.contains("2개"))
        // 폴백 알림에는 건수를 넣지 않는다
        #expect(plan.dropFirst().allSatisfy { !$0.body.contains("개 있어요") })
        #expect(plan.last?.fireDate == date(seoul, 2026, 10, 29, 22, 0))
    }

    @Test func firesTomorrowAfterReminderTime() {
        let seoul = calendar("Asia/Seoul")
        let now = date(seoul, 2026, 10, 23, 23, 30)
        let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 22 * 60, now: now, calendar: seoul)

        #expect(plan.first?.fireDate == date(seoul, 2026, 10, 24, 22, 0))
    }

    @Test func keepsLocalWallClockAcrossDaylightSaving() {
        // 2026-03-08 미국 동부 서머타임 시작
        let newYork = calendar("America/New_York")
        let now = date(newYork, 2026, 3, 6, 23, 0)
        let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 22 * 60, now: now, calendar: newYork)

        #expect(plan.allSatisfy { newYork.component(.hour, from: $0.fireDate) == 22 })
    }

    @Test func identifiersAreStableSoRefreshReplacesPreviousSchedule() {
        let plan = ReminderScheduler.plan(pendingCount: 1, enabled: true, minutes: 9 * 60 + 30, now: .now)
        #expect(plan.map(\.identifier) == ReminderScheduler.allIdentifiers)
    }
}
