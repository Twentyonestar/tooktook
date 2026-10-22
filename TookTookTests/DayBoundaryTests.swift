import Foundation
import Testing
@testable import TookTook

@MainActor
struct DayBoundaryTests {
    private func calendar(_ identifier: String = "Asia/Seoul") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    @Test func clockOnlyMovesWhenTicked() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = AppClock(now: start, observeSystemChanges: false)
        #expect(clock.now == start)

        let later = start.addingTimeInterval(60)
        clock.tick(to: later)
        #expect(clock.now == later)
    }

    @Test func midnightMovesTodayTotal() throws {
        let seoul = calendar()
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let category = try #require(try t.all(ExpenseCategory.self).first)
        let stack = try t.store.createStack(source: .appIntent, at: date(seoul, 2026, 10, 23, 23, 50))
        try t.store.complete(stack, amountKRW: 5_000, categoryId: category.id, occurredAt: stack.createdAt, memo: "")
        let transactions = try t.all(LedgerTransaction.self)

        #expect(LedgerPeriod.todayTotal(transactions, now: date(seoul, 2026, 10, 23, 23, 59, 59), calendar: seoul) == 5_000)
        #expect(LedgerPeriod.todayTotal(transactions, now: date(seoul, 2026, 10, 24, 0, 0), calendar: seoul) == 0)
    }

    @Test func stackCreatedBeforeMidnightStaysPending() throws {
        let seoul = calendar()
        let t = try TestStore()
        let stack = try t.store.createStack(source: .appIntent, at: date(seoul, 2026, 10, 23, 23, 59))
        let createdAt = stack.createdAt
        let pending = [stack]

        #expect(LedgerPeriod.todayPendingCount(pending, now: date(seoul, 2026, 10, 23, 23, 59, 30), calendar: seoul) == 1)
        // 자정이 지나면 '오늘' 건수에서는 빠지지만 미정리 상태와 생성 시각은 그대로다 (BR-08)
        #expect(LedgerPeriod.todayPendingCount(pending, now: date(seoul, 2026, 10, 24, 0, 0), calendar: seoul) == 0)
        #expect(t.store.pendingCount() == 1)
        #expect(stack.createdAt == createdAt)
    }

    @Test func currentMonthAdvancesAtMonthEnd() {
        let seoul = calendar()
        let viewing = seoul.startOfMonth(for: date(seoul, 2026, 10, 1, 0))
        let next = LedgerPeriod.displayedMonth(
            viewing,
            previousNow: date(seoul, 2026, 10, 31, 23, 59),
            now: date(seoul, 2026, 11, 1, 0, 0),
            calendar: seoul
        )
        #expect(next == date(seoul, 2026, 11, 1, 0))
    }

    @Test func pastMonthStaysWhenMonthChanges() {
        let seoul = calendar()
        let viewing = date(seoul, 2026, 8, 1, 0)
        let next = LedgerPeriod.displayedMonth(
            viewing,
            previousNow: date(seoul, 2026, 10, 31, 23, 59),
            now: date(seoul, 2026, 11, 1, 0, 0),
            calendar: seoul
        )
        #expect(next == viewing)
    }

    @Test func midnightWithinMonthKeepsMonth() {
        let seoul = calendar()
        let viewing = date(seoul, 2026, 10, 1, 0)
        let next = LedgerPeriod.displayedMonth(
            viewing,
            previousNow: date(seoul, 2026, 10, 23, 23, 59),
            now: date(seoul, 2026, 10, 24, 0, 0),
            calendar: seoul
        )
        #expect(next == viewing)
    }

    @Test func yearRolloverMovesToJanuary() {
        let seoul = calendar()
        let viewing = date(seoul, 2026, 12, 1, 0)
        let next = LedgerPeriod.displayedMonth(
            viewing,
            previousNow: date(seoul, 2026, 12, 31, 23, 59),
            now: date(seoul, 2027, 1, 1, 0, 0),
            calendar: seoul
        )
        #expect(next == date(seoul, 2027, 1, 1, 0))
    }

    @Test func timeZoneChangeDecidesWhichDayIsToday() {
        // 같은 순간이라도 기기 시간대에 따라 '오늘'이 달라진다. 저장된 시각 자체는 바뀌지 않는다.
        let seoul = calendar("Asia/Seoul")
        let losAngeles = calendar("America/Los_Angeles")
        let spentAt = date(seoul, 2026, 10, 24, 9, 0)   // LA 기준 10월 23일 17시
        let now = date(seoul, 2026, 10, 24, 10, 0)

        #expect(LedgerPeriod.isToday(spentAt, now: now, calendar: seoul))
        #expect(LedgerPeriod.isToday(spentAt, now: now, calendar: losAngeles))
        #expect(!LedgerPeriod.isToday(spentAt, now: date(seoul, 2026, 10, 24, 18, 0), calendar: losAngeles))
    }
}
