import SwiftData
import SwiftUI

struct CompletionSession: Identifiable {
    let id = UUID()
    let stacks: [Stack]
}

struct InboxView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(PrefKey.reminderEnabled) private var reminderEnabled = true

    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" }, sort: \Stack.createdAt)
    private var pendingStacks: [Stack]

    @Query(filter: #Predicate<Stack> { $0.statusRaw == "completed" }, sort: \Stack.createdAt, order: .reverse)
    private var completedStacks: [Stack]

    @Query private var transactions: [LedgerTransaction]
    @Query private var categories: [ExpenseCategory]

    @State private var session: CompletionSession?
    @State private var lastDiscarded: Stack?
    @State private var undoTask: Task<Void, Never>?
    @State private var notificationPermission = NotificationPermission.shared
    @State private var clock = AppClock.shared
    @State private var errorMessage: String?

    private var store: StackStore { StackStore(context: context) }

    private var todayPendingCount: Int {
        LedgerPeriod.todayPendingCount(pendingStacks, now: clock.now, calendar: clock.calendar)
    }

    private var completedToday: [Stack] {
        completedStacks.filter { stack in
            guard let completedAt = stack.completedAt else { return false }
            return LedgerPeriod.isToday(completedAt, now: clock.now, calendar: clock.calendar)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if notificationPermission.availability(enabled: reminderEnabled) == .blockedBySystem {
                    Section {
                        NotificationDeniedBanner()
                    }
                }

                Section {
                    summary
                }

                Section("정리 대기") {
                    if pendingStacks.isEmpty {
                        Text("정리할 스택이 없어요. 결제할 때 iPhone 뒷면을 두 번 톡톡 두드려 보세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingStacks) { stack in
                            Button {
                                startSession(from: stack)
                            } label: {
                                StackRow(stack: stack, now: clock.now)
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button(role: .destructive) {
                                    discard(stack)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !completedToday.isEmpty {
                    Section("오늘 정리한 스택") {
                        ForEach(completedToday) { stack in
                            CompletedStackRow(
                                stack: stack,
                                transaction: transactions.first { $0.id == stack.transactionId },
                                categories: categories
                            )
                        }
                    }
                }
            }
            .navigationTitle("스택")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addStackManually()
                    } label: {
                        Label("스택 추가", systemImage: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if lastDiscarded != nil {
                    undoToast
                }
            }
            .animation(.default, value: lastDiscarded?.id)
            .fullScreenCover(item: $session) { session in
                CompletionFlowView(stacks: session.stacks)
            }
            .errorAlert($errorMessage)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘 남긴 미정리 스택")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(todayPendingCount)개")
                        .font(.largeTitle.bold())
                }
                Spacer()
                if pendingStacks.count > todayPendingCount {
                    Text("전체 대기 \(pendingStacks.count)개")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                session = CompletionSession(stacks: pendingStacks)
            } label: {
                Text("모두 정리하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fontWeight(.semibold)
            .disabled(pendingStacks.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private var undoToast: some View {
        HStack {
            Text("스택을 삭제했어요")
            Spacer()
            Button("실행 취소") { undoDiscard() }
                .bold()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 선택한 스택부터 시작해 남은 미정리 스택을 이어서 정리한다.
    private func startSession(from stack: Stack) {
        guard let index = pendingStacks.firstIndex(where: { $0.id == stack.id }) else { return }
        let ordered = Array(pendingStacks[index...]) + Array(pendingStacks[..<index])
        session = CompletionSession(stacks: ordered)
    }

    private func addStackManually() {
        do {
            let stack = try store.createStack(source: .inApp)
            Task { await LocationEnricher.attachLocation(to: stack, in: context) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard(_ stack: Stack) {
        do {
            try store.discard(stack)
            lastDiscarded = stack
            undoTask?.cancel()
            undoTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                lastDiscarded = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoDiscard() {
        guard let stack = lastDiscarded else { return }
        undoTask?.cancel()
        lastDiscarded = nil
        do {
            try store.restore(stack)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StackRow: View {
    let stack: Stack
    /// AppClock 기준 '지금'. 자정이 지나면 시각만 보이던 행에 날짜가 붙는다.
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeText)
                    .font(.headline)
                Text(stack.placeDisplay.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if stack.isPossibleDuplicate {
                Text("연속 기록")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("금액과 카테고리를 입력해 정리합니다")
    }

    private var timeText: String {
        if LedgerPeriod.isToday(stack.createdAt, now: now, calendar: .autoupdatingCurrent) {
            return stack.createdAt.formatted(date: .omitted, time: .shortened)
        }
        return stack.createdAt.formatted(.dateTime.month().day().hour().minute())
    }
}

struct CompletedStackRow: View {
    let stack: Stack
    let transaction: LedgerTransaction?
    let categories: [ExpenseCategory]

    private var category: ExpenseCategory? {
        guard let transaction else { return nil }
        return categories.first { $0.id == transaction.categoryId }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.symbol ?? "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? "정리 완료")
                Text(stack.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let transaction {
                Text(transaction.amountKRW.krwText)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NotificationDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("정리 알림이 꺼져 있어요", systemImage: "bell.slash")
                .font(.headline)
            Text("iPhone 설정에서 알림을 허용하면 원하는 시간에 미정리 스택을 알려드릴게요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("알림 설정 열기") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
