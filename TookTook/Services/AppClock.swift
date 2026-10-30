import Foundation
import Observation
import UIKit

/// 화면이 쓰는 '지금'. 자정·시간대 변경·앱 복귀 때만 갱신해서, 앱을 켜 둔 채 날짜가 바뀌어도
/// '오늘'과 '이번 달'이 따라오게 한다. 주기 타이머는 쓰지 않는다.
@MainActor
@Observable
final class AppClock {
    static let shared = AppClock()

    private(set) var now: Date
    /// 시간대·달력 설정 변경을 자동으로 따르는 달력
    let calendar: Calendar = .autoupdatingCurrent

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(now: Date = .now, observeSystemChanges: Bool = true) {
        self.now = now
        guard observeSystemChanges else { return }
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func tick(to date: Date = .now) {
        now = date
    }
}

/// 날짜 경계 계산. 화면과 테스트가 같은 규칙을 쓰도록 '지금'과 달력을 인자로 받는다.
enum LedgerPeriod {
    static func isToday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    static func todayTotal(_ transactions: [LedgerTransaction], now: Date, calendar: Calendar) -> Int64 {
        transactions
            .filter { isToday($0.occurredAt, now: now, calendar: calendar) }
            .reduce(0) { $0 + $1.amountKRW }
    }

    /// 날짜별로 묶는다. 최근 날짜가 먼저 오고, 같은 날 안에서는 받은 순서를 유지한다.
    static func groupedByDay<Item>(_ items: [Item], date: (Item) -> Date, calendar: Calendar) -> [(day: Date, items: [Item])] {
        Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// 오늘이면 0, 어제면 1. 섹션 제목을 '오늘'·'어제'로 쓸지 정할 때 쓴다.
    static func daysAgo(_ day: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0
    }

    static func todayPendingCount(_ pending: [Stack], now: Date, calendar: Calendar) -> Int {
        pending.filter { isToday($0.createdAt, now: now, calendar: calendar) }.count
    }

    /// 사용자가 '이번 달'을 보고 있었다면 달이 바뀔 때 새 달로 넘기고, 지난 달을 보고 있었다면 그대로 둔다.
    static func displayedMonth(_ month: Date, previousNow: Date, now: Date, calendar: Calendar) -> Date {
        guard calendar.isDate(month, inSameMonthAs: previousNow) else { return month }
        return calendar.startOfMonth(for: now)
    }
}
