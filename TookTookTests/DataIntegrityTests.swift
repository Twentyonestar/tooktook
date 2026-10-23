import Foundation
import SwiftData
import Testing
@testable import TookTook

@MainActor
struct UniqueIDTests {
    @Test func regeneratesWhenTakenAndNeverReusesExisting() {
        var asked = 0
        let id = UniqueID.make { _ in
            asked += 1
            return asked == 1   // 첫 후보는 이미 있다고 가정
        }
        #expect(asked == 2)
        _ = id
    }

    @Test func storeCreatesDistinctIDsEvenInBursts() throws {
        let t = try TestStore()
        var ids: Set<UUID> = []
        for _ in 0..<50 { ids.insert(try t.store.createStack(source: .appIntent).id) }
        #expect(ids.count == 50)
    }

    @Test func newStackIDSkipsAnExistingID() throws {
        let t = try TestStore()
        let existing = try t.store.createStack(source: .appIntent)
        let isTaken: (UUID) -> Bool = { id in (try? t.context.fetchCount(FetchDescriptor<Stack>(predicate: #Predicate { $0.id == id }))) ?? 0 > 0 }
        #expect(isTaken(existing.id))
        #expect(!isTaken(UniqueID.newStackID(in: t.context)))
    }
}

@MainActor
struct DuplicateIDResolverTests {
    @Test func identicalCopiesCollapseToOne() throws {
        let t = try TestStore()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<3 {
            t.context.insert(Stack(id: id, createdAt: date, captureSource: .appIntent))
        }
        try t.context.save()

        let report = try DuplicateIDResolver.resolve(in: t.context)

        #expect(report.removedIdenticalCopies == 2)
        #expect(try t.all(Stack.self).filter { $0.id == id }.count == 1)
    }

    @Test func differingRecordsWithSameIDAreLeftAlone() throws {
        let t = try TestStore()
        let id = UUID()
        let category = UUID()
        t.context.insert(LedgerTransaction(id: id, sourceStackId: nil, amountKRW: 1_000, categoryId: category, occurredAt: .now, memo: nil))
        t.context.insert(LedgerTransaction(id: id, sourceStackId: nil, amountKRW: 9_000, categoryId: category, occurredAt: .now, memo: "다름"))
        try t.context.save()

        let report = try DuplicateIDResolver.resolve(in: t.context)

        #expect(report.removedIdenticalCopies == 0)
        #expect(report.conflictingIDs["LedgerTransaction"] == [id])
        #expect(Set(try t.all(LedgerTransaction.self).map(\.amountKRW)) == [1_000, 9_000])
    }

    @Test func cleanStoreIsUntouched() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        try t.store.createStack(source: .appIntent)
        #expect(try DuplicateIDResolver.resolve(in: t.context).isClean)
    }
}

@MainActor
struct DefaultCategoryTests {
    @Test func newInstallSeedsFixedIDsAndKeys() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        let categories = try t.all(ExpenseCategory.self).sorted { $0.displayOrder < $1.displayOrder }
        #expect(categories.map(\.id) == DefaultCategory.all.map(\.fixedID))
        #expect(categories.map(\.defaultKey) == DefaultCategory.all.map(\.key))
        #expect(categories.map(\.name) == ["식비", "카페", "교통", "쇼핑", "생활", "문화", "의료", "기타"])
    }

    @Test func twoDevicesSeedingGiveTheSameRecords() throws {
        let a = try TestStore(), b = try TestStore()
        a.store.seedDefaultCategoriesIfNeeded()
        b.store.seedDefaultCategoriesIfNeeded()
        #expect(Set(try a.all(ExpenseCategory.self).map(\.id)) == Set(try b.all(ExpenseCategory.self).map(\.id)))
    }

    @Test func mergeMovesTransactionsToTheCanonicalCategoryAndArchivesTheOther() throws {
        let t = try TestStore()
        let food = DefaultCategory.forKey("food")!
        let canonical = ExpenseCategory(id: food.fixedID, name: "식비", symbol: food.symbol, displayOrder: 0, defaultKey: "food")
        let otherDevice = ExpenseCategory(id: UUID(), name: "식비", symbol: food.symbol, displayOrder: 0, defaultKey: "food")
        let userFood = ExpenseCategory(id: UUID(), name: "식비", symbol: food.symbol, displayOrder: 9)
        [canonical, otherDevice, userFood].forEach(t.context.insert)
        let moved = LedgerTransaction(sourceStackId: nil, amountKRW: 3_000, categoryId: otherDevice.id, occurredAt: .now, memo: nil)
        let untouched = LedgerTransaction(sourceStackId: nil, amountKRW: 4_000, categoryId: userFood.id, occurredAt: .now, memo: nil)
        t.context.insert(moved)
        t.context.insert(untouched)
        try t.context.save()

        #expect(try DefaultCategoryMerger.mergeDuplicates(in: t.context) == 1)

        #expect(moved.categoryId == canonical.id)
        #expect(untouched.categoryId == userFood.id)          // 사용자 카테고리는 병합 대상 아님
        #expect(otherDevice.isArchived)                        // 지우지 않고 보관
        #expect(otherDevice.defaultKey == nil)
        #expect(!canonical.isArchived)
        #expect(try t.all(ExpenseCategory.self).count == 3)    // 삭제 없음
    }

    @Test func mergeKeepsRenamedCanonicalNameAndPrefersMostUsedWithoutFixedID() throws {
        let t = try TestStore()
        let a = ExpenseCategory(id: UUID(), name: "커피", symbol: "cup.and.saucer.fill", displayOrder: 1, defaultKey: "cafe")
        let b = ExpenseCategory(id: UUID(), name: "카페", symbol: "cup.and.saucer.fill", displayOrder: 1, defaultKey: "cafe")
        [a, b].forEach(t.context.insert)
        for _ in 0..<2 { t.context.insert(LedgerTransaction(sourceStackId: nil, amountKRW: 1, categoryId: a.id, occurredAt: .now, memo: nil)) }
        t.context.insert(LedgerTransaction(sourceStackId: nil, amountKRW: 1, categoryId: b.id, occurredAt: .now, memo: nil))
        try t.context.save()

        try DefaultCategoryMerger.mergeDuplicates(in: t.context)

        #expect(!a.isArchived)
        #expect(a.name == "커피")
        #expect(b.isArchived)
        #expect(try t.all(LedgerTransaction.self).allSatisfy { $0.categoryId == a.id })
    }

    @Test func archivedEverywhereStaysArchived() throws {
        let t = try TestStore()
        let a = ExpenseCategory(id: UUID(), name: "의료", symbol: "cross.case.fill", displayOrder: 6, isArchived: true, defaultKey: "medical")
        let b = ExpenseCategory(id: UUID(), name: "의료", symbol: "cross.case.fill", displayOrder: 6, isArchived: true, defaultKey: "medical")
        [a, b].forEach(t.context.insert)
        try t.context.save()
        try DefaultCategoryMerger.mergeDuplicates(in: t.context)
        #expect(a.isArchived && b.isArchived)
    }

    @Test func noDuplicatesMeansNoChanges() throws {
        let t = try TestStore()
        t.store.seedDefaultCategoriesIfNeeded()
        #expect(try DefaultCategoryMerger.mergeDuplicates(in: t.context) == 0)
        #expect(try t.all(ExpenseCategory.self).allSatisfy { !$0.isArchived && $0.defaultKey != nil })
    }

    @Test func launchTaggingOnlyWhenNothingIsTagged() throws {
        let untagged = try TestStore()
        let seeded = ExpenseCategory(id: UUID(), name: "식비", symbol: "fork.knife", displayOrder: 0)
        untagged.context.insert(seeded)
        DefaultCategory.tagIfNeverTagged(in: untagged.context)
        #expect(seeded.defaultKey == "food")

        let tagged = try TestStore()
        tagged.context.insert(ExpenseCategory(id: UUID(), name: "식비", symbol: "fork.knife", displayOrder: 0, defaultKey: "food"))
        let lookalike = ExpenseCategory(id: UUID(), name: "카페", symbol: "cup.and.saucer.fill", displayOrder: 1)
        tagged.context.insert(lookalike)
        DefaultCategory.tagIfNeverTagged(in: tagged.context)
        #expect(lookalike.defaultKey == nil)
    }

    @Test func taggingNeedsExactSeedMatchAndASingleCandidate() throws {
        let t = try TestStore()
        let seeded = ExpenseCategory(id: UUID(), name: "교통", symbol: "bus.fill", displayOrder: 2)
        let wrongOrder = ExpenseCategory(id: UUID(), name: "쇼핑", symbol: "bag.fill", displayOrder: 5)
        let twinA = ExpenseCategory(id: UUID(), name: "생활", symbol: "house.fill", displayOrder: 4)
        let twinB = ExpenseCategory(id: UUID(), name: "생활", symbol: "house.fill", displayOrder: 4)
        let all = [seeded, wrongOrder, twinA, twinB]
        all.forEach(t.context.insert)

        DefaultCategory.tagSeededDefaults(in: all)

        #expect(seeded.defaultKey == "transport")
        #expect(wrongOrder.defaultKey == nil)
        #expect(twinA.defaultKey == nil && twinB.defaultKey == nil)   // 후보가 둘이면 고르지 않는다
    }
}

@MainActor
struct BackupDefaultKeyTests {
    @Test func roundTripKeepsDefaultKeys() throws {
        let source = try TestStore()
        source.store.seedDefaultCategoriesIfNeeded()
        let data = try BackupService.encode(try BackupService.makePayload(from: source.context))

        let target = try TestStore()
        try BackupService.restore(try BackupService.decode(data), into: target.context)

        #expect(Set(try target.all(ExpenseCategory.self).compactMap(\.defaultKey)) == Set(DefaultCategory.all.map(\.key)))
    }

    @Test func olderBackupWithoutKeysGetsTaggedOnRestore() throws {
        // SchemaV1 앱이 만든 백업: defaultKey 없음, 기본 카테고리 ID는 기기마다 랜덤
        var categories: [BackupPayload.CategoryRecord] = DefaultCategory.all.enumerated().map { index, definition in
            .init(id: UUID(), name: definition.name, symbol: definition.symbol, displayOrder: index, isArchived: false, defaultKey: nil)
        }
        categories.append(.init(id: UUID(), name: "술자리", symbol: "wineglass.fill", displayOrder: 8, isArchived: false, defaultKey: nil))
        let payload = BackupPayload(exportedAt: .now, categories: categories, stacks: [], transactions: [])

        let target = try TestStore()
        try BackupService.restore(payload, into: target.context)
        let restored = try target.all(ExpenseCategory.self)

        #expect(restored.filter { $0.defaultKey != nil }.count == 8)
        #expect(restored.first { $0.name == "술자리" }?.defaultKey == nil)
        // ID는 백업 그대로
        #expect(Set(restored.map(\.id)) == Set(categories.map(\.id)))
    }
}
