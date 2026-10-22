import Foundation
import Testing
@testable import TookTook

@MainActor
struct StackStoreTests {
    @Test func stacksWithinThreeSecondsAreFlaggedButKept() throws {
        let t = try TestStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try t.store.createStack(source: .appIntent, at: base)
        let second = try t.store.createStack(source: .appIntent, at: base.addingTimeInterval(2))
        let third = try t.store.createStack(source: .appIntent, at: base.addingTimeInterval(10))

        #expect(first.isPossibleDuplicate == false)
        #expect(second.isPossibleDuplicate == true)
        #expect(third.isPossibleDuplicate == false)
        // 중복 의심이라도 삭제하지 않는다 (BR-10)
        #expect(try t.all(Stack.self).count == 3)
        #expect(t.store.pendingCount() == 3)
    }

    @Test func flaggedStackCanBeCompletedNormally() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let category = try #require(try t.all(ExpenseCategory.self).first)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try t.store.createStack(source: .appIntent, at: base)
        let flagged = try t.store.createStack(source: .appIntent, at: base.addingTimeInterval(1))

        try t.store.complete(flagged, amountKRW: 3000, categoryId: category.id, occurredAt: flagged.createdAt, memo: "")

        #expect(flagged.status == .completed)
        #expect(t.store.pendingCount() == 1)
    }

    @Test func amountMustBePositive() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let category = try #require(try t.all(ExpenseCategory.self).first)
        let stack = try t.store.createStack(source: .inApp)

        #expect(throws: StoreError.self) {
            try t.store.complete(stack, amountKRW: 0, categoryId: category.id, occurredAt: .now, memo: "")
        }
        #expect(stack.status == .pending)
        #expect(try t.all(LedgerTransaction.self).isEmpty)
    }

    @Test func completionLinksStackAndTransaction() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let category = try #require(try t.all(ExpenseCategory.self).first)
        let stack = try t.store.createStack(source: .appIntent)
        let createdAt = stack.createdAt
        let editedTime = createdAt.addingTimeInterval(-600)

        try t.store.complete(stack, amountKRW: 12_500, categoryId: category.id, occurredAt: editedTime, memo: "  점심 ")

        let transaction = try #require(try t.all(LedgerTransaction.self).first)
        #expect(stack.transactionId == transaction.id)
        #expect(transaction.sourceStackId == stack.id)
        #expect(transaction.memo == "점심")
        #expect(transaction.occurredAt == editedTime)
        // 결제 시각을 바꿔도 스택 생성 시각은 유지 (BR-05)
        #expect(stack.createdAt == createdAt)
    }

    @Test func deletingTransactionDiscardsItsStack() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let category = try #require(try t.all(ExpenseCategory.self).first)
        let stack = try t.store.createStack(source: .appIntent)
        try t.store.complete(stack, amountKRW: 1000, categoryId: category.id, occurredAt: .now, memo: "")
        let transaction = try #require(try t.all(LedgerTransaction.self).first)

        try t.store.delete(transaction)

        #expect(stack.status == .discarded)
        #expect(stack.transactionId == nil)
        #expect(t.store.pendingCount() == 0)
    }

    @Test func discardCanBeUndone() throws {
        let t = try TestStore()
        let stack = try t.store.createStack(source: .appIntent)

        try t.store.discard(stack)
        #expect(t.store.pendingCount() == 0)

        try t.store.restore(stack)
        #expect(t.store.pendingCount() == 1)
    }
}
