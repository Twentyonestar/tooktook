import SwiftData
import SwiftUI

/// 여러 스택을 순서대로 정리하는 화면 (Flow B·C)
struct CompletionFlowView: View {
    @Environment(\.dismiss) private var dismiss

    private let stacks: [Stack]
    @State private var index = 0
    @State private var finished = false

    init(stacks: [Stack]) {
        self.stacks = stacks
    }

    var body: some View {
        NavigationStack {
            Group {
                if finished || stacks.isEmpty {
                    CompletionSummaryView { dismiss() }
                } else {
                    StackCompletionForm(
                        stack: stacks[index],
                        position: index + 1,
                        total: stacks.count,
                        onFinish: advance
                    )
                    .id(stacks[index].id)
                }
            }
            .toolbar {
                if !finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
        }
    }

    private func advance() {
        // 다른 경로(단축어 등)로 이미 처리된 스택은 건너뛴다.
        var next = index + 1
        while next < stacks.count, stacks[next].status != .pending {
            next += 1
        }
        if next < stacks.count {
            index = next
        } else {
            finished = true
        }
    }
}

struct StackCompletionForm: View {
    let stack: Stack
    let position: Int
    let total: Int
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ExpenseCategory> { !$0.isArchived }, sort: \ExpenseCategory.displayOrder)
    private var categories: [ExpenseCategory]

    @State private var amountText = ""
    @State private var categoryId: UUID?
    @State private var memo = ""
    @State private var occurredAt: Date
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    init(stack: Stack, position: Int, total: Int, onFinish: @escaping () -> Void) {
        self.stack = stack
        self.position = position
        self.total = total
        self.onFinish = onFinish
        _occurredAt = State(initialValue: stack.createdAt)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stack.createdAt.formatted(.dateTime.month().day().weekday().hour().minute()))
                        .font(.headline)
                    Label(stack.placeDisplay.text, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    if stack.isPossibleDuplicate {
                        Text("바로 앞 스택과 3초 안에 남겨졌어요. 연달아 결제했다면 그대로 정리하면 돼요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if stack.placeDisplay.canRetry {
                    Button("장소 다시 확인") {
                        Task { await LocationEnricher.retryPlaceLookup(for: stack, in: context) }
                    }
                }
            }

            Section("금액") {
                AmountField(text: $amountText)
                    .focused($amountFocused)
            }

            Section("카테고리") {
                CategoryGrid(categories: categories, selection: $categoryId)
            }

            Section("메모") {
                TextField("선택 입력", text: $memo)
            }

            Section("결제 시각") {
                DatePicker("결제 시각", selection: $occurredAt)
            }
        }
        .navigationTitle("\(position) / \(total)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    onFinish()
                } label: {
                    Text("건너뛰기").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    save()
                } label: {
                    Text(position < total ? "저장하고 다음" : "저장").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseAmount(amountText) <= 0 || categoryId == nil)
            }
            .controlSize(.large)
            .fontWeight(.semibold)
            .padding()
            .background(.bar)
        }
        .errorAlert($errorMessage)
        .onAppear { amountFocused = true }
    }

    private func save() {
        do {
            try StackStore(context: context).complete(
                stack,
                amountKRW: parseAmount(amountText),
                categoryId: categoryId,
                occurredAt: occurredAt,
                memo: memo
            )
            onFinish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AmountField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                TextField("0", text: $text)
                .keyboardType(.numberPad)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .accessibilityLabel("금액")
                .onChange(of: text) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(12))
                    if digits != newValue { text = digits }
                }
                Text("원")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            if parseAmount(text) > 0 {
                Text(parseAmount(text).krwText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoryGrid: View {
    let categories: [ExpenseCategory]
    @Binding var selection: UUID?

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(categories) { category in
                let isSelected = selection == category.id
                Button {
                    selection = category.id
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.title3)
                        Text(category.name)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct CompletionSummaryView: View {
    let onClose: () -> Void

    @Query private var transactions: [LedgerTransaction]
    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" })
    private var pendingStacks: [Stack]

    private var todayTotal: Int64 {
        transactions
            .filter { Calendar.current.isDateInToday($0.occurredAt) }
            .reduce(0) { $0 + $1.amountKRW }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(pendingStacks.isEmpty ? "모두 정리했어요" : "정리를 마쳤어요")
                .font(.title.bold())
            VStack(spacing: 4) {
                Text("오늘의 지출 합계")
                    .foregroundStyle(.secondary)
                Text(todayTotal.krwText)
                    .font(.largeTitle.bold())
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            if !pendingStacks.isEmpty {
                Text("건너뛴 스택 \(pendingStacks.count)개는 목록에 남아 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Text("닫기").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fontWeight(.semibold)
        }
        .padding()
    }
}
