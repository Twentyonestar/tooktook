import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTransaction.occurredAt, order: .reverse) private var transactions: [LedgerTransaction]
    @Query private var categories: [ExpenseCategory]

    @State private var clock = AppClock.shared
    @State private var month = AppClock.shared.calendar.startOfMonth(for: AppClock.shared.now)
    @State private var errorMessage: String?

    private var monthTransactions: [LedgerTransaction] {
        transactions.filter { clock.calendar.isDate($0.occurredAt, inSameMonthAs: month) }
    }

    private var days: [(day: Date, items: [LedgerTransaction])] {
        Dictionary(grouping: monthTransactions) { clock.calendar.startOfDay(for: $0.occurredAt) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                    HStack {
                        Text("이번 달 확정 지출")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(monthTransactions.reduce(0) { $0 + $1.amountKRW }.krwText)
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }

                if days.isEmpty {
                    Text("이 달에 정리한 지출이 없어요.")
                        .foregroundStyle(.secondary)
                }

                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            NavigationLink {
                                TransactionEditView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction, category: category(for: transaction))
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { group.items[$0] })
                        }
                    } header: {
                        HStack {
                            Text(group.day.formatted(.dateTime.month().day().weekday()))
                            Spacer()
                            Text(group.items.reduce(0) { $0 + $1.amountKRW }.krwText)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("내역")
            .onChange(of: clock.now) { previous, now in
                month = LedgerPeriod.displayedMonth(month, previousNow: previous, now: now, calendar: clock.calendar)
            }
            .errorAlert($errorMessage)
        }
    }

    private func category(for transaction: LedgerTransaction) -> ExpenseCategory? {
        categories.first { $0.id == transaction.categoryId }
    }

    private func delete(_ items: [LedgerTransaction]) {
        let store = StackStore(context: context)
        do {
            for item in items {
                try store.delete(item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TransactionRow: View {
    let transaction: LedgerTransaction
    let category: ExpenseCategory?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.symbol ?? "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? "알 수 없음")
                Text([transaction.occurredAt.formatted(date: .omitted, time: .shortened), transaction.memo]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(transaction.amountKRW.krwText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct TransactionEditView: View {
    let transaction: LedgerTransaction

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseCategory.displayOrder) private var categories: [ExpenseCategory]

    @State private var amountText: String
    @State private var categoryId: UUID?
    @State private var occurredAt: Date
    @State private var memo: String
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        _amountText = State(initialValue: String(transaction.amountKRW))
        _categoryId = State(initialValue: transaction.categoryId)
        _occurredAt = State(initialValue: transaction.occurredAt)
        _memo = State(initialValue: transaction.memo ?? "")
    }

    private var sourceStack: Stack? {
        guard let id = transaction.sourceStackId else { return nil }
        return StackStore(context: context).stack(id: id)
    }

    /// 보관된 카테고리라도 이 거래가 쓰고 있다면 선택지에 보여준다.
    private var selectableCategories: [ExpenseCategory] {
        categories.filter { !$0.isArchived || $0.id == transaction.categoryId }
    }

    var body: some View {
        Form {
            Section("금액") {
                AmountField(text: $amountText)
            }
            Section("카테고리") {
                CategoryGrid(categories: selectableCategories, selection: $categoryId)
            }
            Section("메모") {
                TextField("선택 입력", text: $memo)
            }
            Section {
                DatePicker("결제 시각", selection: $occurredAt)
                if let stack = sourceStack {
                    LabeledContent("스택 생성 시각", value: stack.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let place = stack.placeLabel {
                        LabeledContent("위치", value: place)
                    }
                }
            } footer: {
                if sourceStack != nil {
                    Text("결제 시각을 바꿔도 원래 스택을 남긴 시각은 유지돼요.")
                }
            }
            Section {
                Button("이 기록 삭제", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("지출 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { save() }
                    .disabled(parseAmount(amountText) <= 0 || categoryId == nil)
            }
        }
        .confirmationDialog("이 지출 기록을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { delete() }
        }
        .errorAlert($errorMessage)
    }

    private func save() {
        do {
            try StackStore(context: context).update(
                transaction,
                amountKRW: parseAmount(amountText),
                categoryId: categoryId,
                occurredAt: occurredAt,
                memo: memo
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try StackStore(context: context).delete(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
