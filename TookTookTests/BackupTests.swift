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

    @Test func saveFailureDuringRestoreKeepsExistingData() throws {
        // 기기에 이미 있는 데이터
        let target = try TestStore()
        let (_, completed) = try makeSampleData(in: target)
        let before = (
            stacks: try target.all(Stack.self).map(\.id).sorted { $0.uuidString < $1.uuidString },
            transactions: try target.all(LedgerTransaction.self).map(\.id),
            categories: try target.all(ExpenseCategory.self).count
        )

        // 전혀 다른 백업 파일
        let other = try TestStore()
        try other.store.createStack(source: .inApp)
        let payload = try roundTrip(BackupService.makePayload(from: other.context))

        struct DiskFull: Error {}
        #expect(throws: DiskFull.self) {
            try BackupService.restore(payload, into: target.context) { _ in throw DiskFull() }
        }

        #expect(try target.all(Stack.self).map(\.id).sorted { $0.uuidString < $1.uuidString } == before.stacks)
        #expect(try target.all(LedgerTransaction.self).map(\.id) == before.transactions)
        #expect(try target.all(ExpenseCategory.self).count == before.categories)
        let kept = try #require(target.store.stack(id: completed.id))
        #expect(kept.placeLabel == "역삼동")
        #expect(kept.transactionId == before.transactions.first)

        // 저장소에 다시 접근해도(앱 재실행) 같은 상태다
        let reopened = ModelContext(target.container)
        #expect(try reopened.fetchCount(FetchDescriptor<Stack>()) == before.stacks.count)
    }

    @Test func versionOneFileWithoutNewerFieldsStillImports() throws {
        // 장소 재시도 필드(placeLookupAttempts, placeLabelVersion)가 생기기 전 형식
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-10-23T00:00:00Z",
          "categories": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "식비", "symbol": "fork.knife", "displayOrder": 0, "isArchived": false}
          ],
          "stacks": [
            {"id": "22222222-2222-2222-2222-222222222222", "createdAt": "2026-10-22T14:09:58Z",
             "captureSource": "appIntent", "status": "completed", "latitude": 37.4968, "longitude": 126.8802,
             "horizontalAccuracy": 7.4, "locationStatus": "captured", "placeLabel": "구로동 구로동",
             "completedAt": "2026-10-22T14:20:00Z", "transactionId": "33333333-3333-3333-3333-333333333333",
             "isPossibleDuplicate": false}
          ],
          "transactions": [
            {"id": "33333333-3333-3333-3333-333333333333", "sourceStackId": "22222222-2222-2222-2222-222222222222",
             "amountKRW": 12500, "categoryId": "11111111-1111-1111-1111-111111111111",
             "occurredAt": "2026-10-22T14:09:58Z", "createdAt": "2026-10-22T14:20:00Z", "updatedAt": "2026-10-22T14:20:00Z"}
          ]
        }
        """
        let payload = try BackupService.decode(Data(json.utf8))
        let target = try TestStore()
        try BackupService.restore(payload, into: target.context)

        let stack = try #require(try target.all(Stack.self).first)
        #expect(stack.placeLookupAttempts == 0)
        #expect(stack.placeLabelVersion == 0)   // 예전 형식 라벨이라 다음 실행 때 새 형식으로 교체된다
        #expect(try target.all(LedgerTransaction.self).first?.amountKRW == 12_500)
    }

    @Test func roundTripCarriesPlaceRetryState() throws {
        let source = try TestStore()
        let stack = try source.store.createStack(source: .appIntent)
        stack.placeLookupAttempts = 2
        stack.placeLabelVersion = 1
        try source.context.save()

        let target = try TestStore()
        try BackupService.restore(try roundTrip(BackupService.makePayload(from: source.context)), into: target.context)

        let restored = try #require(target.store.stack(id: stack.id))
        #expect(restored.placeLookupAttempts == 2)
        #expect(restored.placeLabelVersion == 1)
    }
}
