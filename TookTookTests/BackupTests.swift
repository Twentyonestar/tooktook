import Foundation
import SwiftData
import Testing
@testable import TookTook

@MainActor
struct BackupTests {
    /// 활성·보관 카테고리, 정리된 스택, 대기 스택, 버린 스택이 섞인 데이터
    private func makeSampleData(in t: TestStore) throws -> (archived: ExpenseCategory, completed: Stack) {
        t.store.seedDefaultCategoriesIfNeeded()
        let categories = try t.all(ExpenseCategory.self).sorted { $0.displayOrder < $1.displayOrder }
        let archived = categories[1]

        let completed = try t.store.createStack(source: .appIntent, at: Date(timeIntervalSince1970: 1_800_000_000))
        completed.latitude = 37.5
        completed.longitude = 127.0
        completed.horizontalAccuracy = 30
        completed.locationStatus = .captured
        completed.placeLabel = "역삼동"
        try t.store.complete(completed, amountKRW: 4_800, categoryId: archived.id, occurredAt: completed.createdAt, memo: "커피")
        archived.isArchived = true

        try t.store.createStack(source: .appIntent, at: Date(timeIntervalSince1970: 1_800_000_100))
        let discarded = try t.store.createStack(source: .inApp, at: Date(timeIntervalSince1970: 1_800_000_200))
        try t.store.discard(discarded)
        return (archived, completed)
    }

    private func roundTrip(_ payload: BackupPayload) throws -> BackupPayload {
        try BackupService.decode(BackupService.encode(payload))
    }

    @Test func roundTripKeepsEveryEntityAndReference() throws {
        let source = try TestStore()
        let (archived, completed) = try makeSampleData(in: source)
        let payload = try roundTrip(BackupService.makePayload(from: source.context))

        let target = try TestStore()
        try BackupService.restore(payload, into: target.context)

        #expect(try target.all(ExpenseCategory.self).count == ExpenseCategory.defaults.count)
        #expect(try target.all(Stack.self).count == 3)
        #expect(try target.all(LedgerTransaction.self).count == 1)
        #expect(target.store.pendingCount() == 1)

        let restoredStack = try #require(target.store.stack(id: completed.id))
        let transaction = try #require(try target.all(LedgerTransaction.self).first)
        #expect(restoredStack.status == .completed)
        #expect(restoredStack.transactionId == transaction.id)
        #expect(restoredStack.placeLabel == "역삼동")
        #expect(restoredStack.locationStatus == .captured)
        #expect(restoredStack.createdAt == completed.createdAt)
        #expect(transaction.sourceStackId == restoredStack.id)
        #expect(transaction.memo == "커피")

        // 보관된 카테고리도 그대로 남아 기존 지출에서 조회된다
        let category = try #require(try target.all(ExpenseCategory.self).first { $0.id == transaction.categoryId })
        #expect(category.id == archived.id)
        #expect(category.isArchived)
    }

    @Test func importingSameBackupTwiceDoesNotDuplicate() throws {
        let source = try TestStore()
        _ = try makeSampleData(in: source)
        let payload = try roundTrip(BackupService.makePayload(from: source.context))

        let target = try TestStore()
        try BackupService.restore(payload, into: target.context)
        try BackupService.restore(payload, into: target.context)

        #expect(try target.all(Stack.self).count == 3)
        #expect(try target.all(LedgerTransaction.self).count == 1)
        #expect(try target.all(ExpenseCategory.self).count == ExpenseCategory.defaults.count)
    }

    @Test func importReplacesExistingData() throws {
        let source = try TestStore()
        _ = try makeSampleData(in: source)
        let payload = try roundTrip(BackupService.makePayload(from: source.context))

        let target = try TestStore()
        try target.store.createStack(source: .inApp)
        try BackupService.restore(payload, into: target.context)

        #expect(try target.all(Stack.self).count == 3)
    }

    @Test func brokenFileIsRejectedAndExistingDataIsKept() throws {
        let source = try TestStore()
        _ = try makeSampleData(in: source)
        var payload = try BackupService.makePayload(from: source.context)
        payload.categories.removeAll()

        let target = try TestStore()
        let existing = try target.store.createStack(source: .inApp)

        #expect(throws: BackupError.self) {
            try BackupService.restore(payload, into: target.context)
        }
        #expect(try target.all(Stack.self).map(\.id) == [existing.id])
    }

    @Test func newerBackupVersionIsRejected() throws {
        var payload = BackupPayload(exportedAt: .now, categories: [], stacks: [], transactions: [])
        payload.version = BackupService.currentVersion + 1
        #expect(throws: BackupError.self) { try BackupService.validate(payload) }
    }
}
