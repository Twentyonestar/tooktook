import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var transactions: [LedgerTransaction]
    @Query private var categories: [ExpenseCategory]
    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" })
    private var pendingStacks: [Stack]

    @State private var clock = AppClock.shared
    @State private var month = AppClock.shared.calendar.startOfMonth(for: AppClock.shared.now)

    private struct CategoryTotal: Identifiable {
        let id: UUID
        let name: String
        let symbol: String
        let amount: Int64
    }

    private struct DayTotal: Identifiable {
        var id: Date { day }
        let day: Date
        let amount: Int64
    }

    private var monthTransactions: [LedgerTransaction] {
        transactions.filter { clock.calendar.isDate($0.occurredAt, inSameMonthAs: month) }
    }

    private var monthTotal: Int64 {
        monthTransactions.reduce(0) { $0 + $1.amountKRW }
    }

    private var categoryTotals: [CategoryTotal] {
        Dictionary(grouping: monthTransactions, by: \.categoryId)
            .map { id, items in
                let category = categories.first { $0.id == id }
                return CategoryTotal(
                    id: id,
                    name: category?.name ?? "알 수 없음",
                    symbol: category?.symbol ?? "questionmark.circle",
                    amount: items.reduce(0) { $0 + $1.amountKRW }
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    private var dayTotals: [DayTotal] {
        Dictionary(grouping: monthTransactions) { clock.calendar.startOfDay(for: $0.occurredAt) }
            .map { DayTotal(day: $0.key, amount: $0.value.reduce(0) { $0 + $1.amountKRW }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("확정 지출 합계")
                            .foregroundStyle(.secondary)
                        Text(monthTotal.krwText)
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    if !pendingStacks.isEmpty {
                        Label("정리 대기 \(pendingStacks.count)건은 합계에 포함되지 않았어요", systemImage: "tray")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if monthTransactions.isEmpty {
                    Text("이 달에 정리한 지출이 없어요.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("카테고리별") {
                        Chart(categoryTotals) { item in
                            SectorMark(
                                angle: .value("금액", item.amount),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("카테고리", item.name))
                        }
                        .frame(height: 220)
                        .accessibilityHidden(true)

                        ForEach(categoryTotals) { item in
                            HStack {
                                Label(item.name, systemImage: item.symbol)
                                Spacer()
                                Text(percentText(item.amount))
                                    .foregroundStyle(.secondary)
                                Text(item.amount.krwText)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Section("일자별 추이") {
                        Chart(dayTotals) { item in
                            BarMark(
                                x: .value("날짜", item.day, unit: .day),
                                y: .value("금액", item.amount)
                            )
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Int64.self) {
                                        Text(compactKRW(amount))
                                    }
                                }
                            }
                        }
                        .frame(height: 200)
                        .accessibilityLabel("일자별 지출 막대그래프")
                    }
                }
            }
            .navigationTitle("통계")
            .onChange(of: clock.now) { previous, now in
                month = LedgerPeriod.displayedMonth(month, previousNow: previous, now: now, calendar: clock.calendar)
            }
        }
    }

    private func percentText(_ amount: Int64) -> String {
        guard monthTotal > 0 else { return "0%" }
        return (Double(amount) / Double(monthTotal)).formatted(.percent.precision(.fractionLength(0)))
    }

    private func compactKRW(_ amount: Int64) -> String {
        amount >= 10_000 ? "\(amount / 10_000)만" : amount.formatted(.number)
    }
}
