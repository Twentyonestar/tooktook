import Foundation
import SwiftData

enum StoreError: LocalizedError {
    case invalidAmount
    case missingCategory

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "금액은 0원보다 커야 해요."
        case .missingCategory: "카테고리를 선택해 주세요."
        }
    }
}

/// 스택·거래·카테고리에 대한 쓰기 작업. 저장에 실패하면 변경을 되돌리고 오류를 던진다.
@MainActor
struct StackStore {
    let context: ModelContext

    /// 이 시간 안에 연속으로 생성된 스택은 중복 가능성만 표시한다.
    static let duplicateWindow: TimeInterval = 3

    // MARK: - Stack

    @discardableResult
    func createStack(source: CaptureSource, at date: Date = .now) throws -> Stack {
        let windowStart = date.addingTimeInterval(-Self.duplicateWindow)
        let recent = FetchDescriptor<Stack>(predicate: #Predicate { $0.createdAt >= windowStart })
        let hasRecent = (try? context.fetchCount(recent)) ?? 0 > 0

        let stack = Stack(createdAt: date, captureSource: source, isPossibleDuplicate: hasRecent)
        context.insert(stack)
        try save()
        return stack
    }

    func complete(_ stack: Stack, amountKRW: Int64, categoryId: UUID?, occurredAt: Date, memo: String) throws {
        guard amountKRW > 0 else { throw StoreError.invalidAmount }
        guard let categoryId else { throw StoreError.missingCategory }

        let transaction = LedgerTransaction(
            sourceStackId: stack.id,
            amountKRW: amountKRW,
            categoryId: categoryId,
            occurredAt: occurredAt,
            memo: memo.nilIfBlank
        )
        context.insert(transaction)
        stack.status = .completed
        stack.completedAt = .now
        stack.transactionId = transaction.id
        stack.discardedAt = nil
        try save()
    }

    func discard(_ stack: Stack) throws {
        stack.status = .discarded
        stack.discardedAt = .now
        try save()
    }

    func restore(_ stack: Stack) throws {
        stack.status = .pending
        stack.discardedAt = nil
        try save()
    }

    func pendingCount() -> Int {
        let pending = StackStatus.pending.rawValue
        let descriptor = FetchDescriptor<Stack>(predicate: #Predicate { $0.statusRaw == pending })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func stack(id: UUID) -> Stack? {
        var descriptor = FetchDescriptor<Stack>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func clearAllLocations() throws {
        for stack in try context.fetch(FetchDescriptor<Stack>()) where stack.hasCoordinate || stack.placeLabel != nil {
            stack.clearLocation()
        }
        try save()
    }

    // MARK: - Transaction

    /// 스택 생성 시각은 그대로 두고 거래 내용만 고친다 (BR-05).
    func update(_ transaction: LedgerTransaction, amountKRW: Int64, categoryId: UUID?, occurredAt: Date, memo: String) throws {
        guard amountKRW > 0 else { throw StoreError.invalidAmount }
        guard let categoryId else { throw StoreError.missingCategory }
        transaction.amountKRW = amountKRW
        transaction.categoryId = categoryId
        transaction.occurredAt = occurredAt
        transaction.memo = memo.nilIfBlank
        transaction.updatedAt = .now
        try save()
    }

    /// 거래를 지우면 연결된 스택은 다시 정리 목록에 나타나지 않도록 버린 상태로 둔다.
    func delete(_ transaction: LedgerTransaction) throws {
        if let stackId = transaction.sourceStackId, let stack = stack(id: stackId) {
            stack.status = .discarded
            stack.discardedAt = .now
            stack.transactionId = nil
        }
        context.delete(transaction)
        try save()
    }

    // MARK: - Category

    func seedDefaultCategoriesIfNeeded() {
        let count = (try? context.fetchCount(FetchDescriptor<ExpenseCategory>())) ?? 0
        guard count == 0 else { return }
        for (index, item) in ExpenseCategory.defaults.enumerated() {
            context.insert(ExpenseCategory(name: item.name, symbol: item.symbol, displayOrder: index))
        }
        try? save()
    }

    func addCategory(name: String, symbol: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let all = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let nextOrder = (all.map(\.displayOrder).max() ?? -1) + 1
        context.insert(ExpenseCategory(name: trimmed, symbol: symbol, displayOrder: nextOrder))
        try save()
    }

    func saveChanges() throws {
        try save()
    }

    // MARK: - All data

    func deleteAllData() throws {
        try context.delete(model: LedgerTransaction.self)
        try context.delete(model: Stack.self)
        try context.delete(model: ExpenseCategory.self)
        try save()
        seedDefaultCategoriesIfNeeded()
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
