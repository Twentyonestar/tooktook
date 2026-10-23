import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import TookTook

/// 버전 관리 이전 앱이 만든 저장소를 새 코드로 여는 검증.
/// 원본 픽스처는 번들에서 임시 폴더로 복사해서만 쓴다.
@MainActor
struct StoreMigrationTests {
    private final class BundleToken {}

    private func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil))
    }

    /// 픽스처 저장소 파일들을 새 임시 폴더로 복사하고 저장소 경로를 돌려준다.
    /// base: "default.store"(StoreV0, 버전 관리 이전) 또는 "storeV1.store"(StoreV1, SchemaV1 앱)
    private func copiedFixtureStore(_ base: String = "default.store") throws -> (store: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [base, base + "-wal", base + "-shm"] {
            try FileManager.default.copyItem(at: try fixtureURL(name), to: folder.appending(path: name))
        }
        return (folder.appending(path: base), folder)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tooktook.store.\(UUID().uuidString)")!
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    @Test func preVersioningStoreOpensWithSchemaV1AndKeepsEveryRecord() throws {
        let (storeURL, folder) = try copiedFixtureStore()
        let container = try Persistence.openContainer(at: storeURL, backupsDirectory: folder.appending(path: "backups"), defaults: freshDefaults())
        let context = ModelContext(container)

        let stacks = try fetch(Stack.self, in: context)
        let transactions = try fetch(LedgerTransaction.self, in: context)
        let categories = try fetch(ExpenseCategory.self, in: context)
        #expect(stacks.count == 5)
        #expect(transactions.count == 2)
        #expect(categories.count == 2)

        let completed = try #require(stacks.first { $0.id == StoreFixture.completedStackID })
        #expect(completed.status == .completed)
        #expect(completed.createdAt == StoreFixture.baseDate)
        #expect(completed.latitude == 37.5)
        #expect(completed.longitude == 127.0)
        #expect(completed.horizontalAccuracy == 12.5)
        #expect(completed.placeLabel == "테스트시 테스트구 테스트동")
        #expect(completed.placeLabelVersion == 1)
        #expect(completed.locationStatus == .captured)

        let pending = try #require(stacks.first { $0.id == StoreFixture.pendingStackID })
        #expect(pending.status == .pending)
        #expect(pending.isPossibleDuplicate)
        #expect(pending.locationStatus == .unauthorized)

        let discarded = try #require(stacks.first { $0.id == StoreFixture.discardedStackID })
        #expect(discarded.status == .discarded)
        #expect(discarded.captureSource == .inApp)
        #expect(discarded.discardedAt != nil)

        let retrying = try #require(stacks.first { $0.id == StoreFixture.retryingStackID })
        #expect(retrying.placeLookupAttempts == 2)
        #expect(retrying.placeDisplay == .retryPending)

        let archived = try #require(categories.first { $0.id == StoreFixture.archivedCategoryID })
        #expect(archived.isArchived)
        #expect(archived.name == "옛 카테고리")
    }

    @Test func uuidLinksSurviveOpening() throws {
        let (storeURL, folder) = try copiedFixtureStore()
        let container = try Persistence.openContainer(at: storeURL, backupsDirectory: folder.appending(path: "backups"), defaults: freshDefaults())
        let context = ModelContext(container)
        let stacks = try fetch(Stack.self, in: context)
        let transactions = try fetch(LedgerTransaction.self, in: context)
        let categoryIDs = Set(try fetch(ExpenseCategory.self, in: context).map(\.id))

        for transaction in transactions {
            #expect(categoryIDs.contains(transaction.categoryId))
            let source = try #require(stacks.first { $0.id == transaction.sourceStackId })
            #expect(source.transactionId == transaction.id)
        }
        let food = try #require(transactions.first { $0.id == StoreFixture.foodTransactionID })
        #expect(food.amountKRW == 12_500)
        #expect(food.memo == "점심")
        #expect(food.occurredAt == StoreFixture.baseDate.addingTimeInterval(-120))
        let archivedSpend = try #require(transactions.first { $0.id == StoreFixture.archivedTransactionID })
        #expect(archivedSpend.categoryId == StoreFixture.archivedCategoryID)
        #expect(archivedSpend.memo == nil)
    }

    @Test func bundledFixtureIsNeverModified() throws {
        let original = try sha256(try fixtureURL("default.store"))
        let (storeURL, folder) = try copiedFixtureStore()
        _ = try Persistence.openContainer(at: storeURL, backupsDirectory: folder.appending(path: "backups"), defaults: freshDefaults())
        #expect(try sha256(try fixtureURL("default.store")) == original)
    }

    @Test func dataSurvivesReopeningAfterWrites() throws {
        let (storeURL, folder) = try copiedFixtureStore()
        let defaults = freshDefaults()
        let backups = folder.appending(path: "backups")
        var newStackID: UUID?
        do {
            let container = try Persistence.openContainer(at: storeURL, backupsDirectory: backups, defaults: defaults)
            let context = ModelContext(container)
            newStackID = try StackStore(context: context).createStack(source: .appIntent).id
        }

        // 앱 재실행
        let reopened = try Persistence.openContainer(at: storeURL, backupsDirectory: backups, defaults: defaults)
        let stacks = try fetch(Stack.self, in: ModelContext(reopened))
        #expect(stacks.count == 6)
        #expect(stacks.contains { $0.id == newStackID })
        #expect(stacks.contains { $0.id == StoreFixture.completedStackID })
    }

    @Test func firstVersionedLaunchCopiesStoreBeforeOpening() throws {
        let (storeURL, folder) = try copiedFixtureStore()
        let backups = folder.appending(path: "backups")
        let defaults = freshDefaults()
        let originalHash = try sha256(storeURL)

        _ = try Persistence.openContainer(at: storeURL, backupsDirectory: backups, defaults: defaults)

        let copies = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(copies.count == 1)
        let copy = backups.appending(path: try #require(copies.first)).appending(path: "default.store")
        #expect(try sha256(copy) == originalHash)
        #expect(defaults.string(forKey: Persistence.schemaVersionKey) == Persistence.currentSchemaVersion)

        // 같은 버전으로 다시 열 때는 사본을 더 만들지 않는다
        _ = try Persistence.openContainer(at: storeURL, backupsDirectory: backups, defaults: defaults)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 1)
    }

    @Test func freshInstallCreatesStoreWithoutBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "fresh-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backups = folder.appending(path: "backups")

        let container = try Persistence.openContainer(at: folder.appending(path: "default.store"), backupsDirectory: backups, defaults: freshDefaults())

        #expect(try fetch(Stack.self, in: ModelContext(container)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test func cloudKitSyncIsExplicitlyOff() throws {
        let (storeURL, folder) = try copiedFixtureStore()
        let container = try Persistence.openContainer(at: storeURL, backupsDirectory: folder.appending(path: "backups"), defaults: freshDefaults())
        // CloudKitDatabase는 Equatable이 아니라 컨테이너 식별자와 설명 문자열로 확인한다.
        for configuration in container.configurations {
            #expect(configuration.cloudKitContainerIdentifier == nil)
            #expect(String(describing: configuration.cloudKitDatabase).localizedCaseInsensitiveContains("none"))
        }
    }

    /// 로컬에서만: 실기기 저장소 사본을 열어 본다. 개인 데이터라 저장소에 커밋하지 않는다.
    /// TEST_RUNNER_TOOKTOOK_EXTERNAL_STORE_DIR=<default.store가 있는 폴더 사본>
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOKTOOK_EXTERNAL_STORE_DIR"] != nil))
    func externalDeviceStoreCopyOpensIntact() throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOOKTOOK_EXTERNAL_STORE_DIR"]!)
        let folder = FileManager.default.temporaryDirectory.appending(path: "device-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: source, to: folder)
        let container = try Persistence.openContainer(
            at: folder.appending(path: "default.store"), backupsDirectory: folder.appending(path: "backups"), defaults: freshDefaults()
        )
        let context = ModelContext(container)
        let stacks = try fetch(Stack.self, in: context)
        let transactions = try fetch(LedgerTransaction.self, in: context)
        let categories = try fetch(ExpenseCategory.self, in: context)
        print("EXTERNAL_STORE stacks=\(stacks.count) transactions=\(transactions.count) categories=\(categories.count)")
        for line in stacks.sorted(by: { $0.createdAt < $1.createdAt }) {
            print("EXTERNAL_STACK \(line.id.uuidString.prefix(8)) \(line.statusRaw) \(line.locationStatusRaw) \(line.placeLabel ?? "-") \(line.transactionId?.uuidString.prefix(8) ?? "-")")
        }
        for category in categories.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            print("EXTERNAL_CATEGORY \(category.id.uuidString.prefix(8)) \(category.name) order=\(category.displayOrder) archived=\(category.isArchived) key=\(category.defaultKey ?? "-")")
        }
        for transaction in transactions {
            print("EXTERNAL_TX \(transaction.id.uuidString.prefix(8)) \(transaction.amountKRW) cat=\(transaction.categoryId.uuidString.prefix(8)) stack=\(transaction.sourceStackId?.uuidString.prefix(8) ?? "-")")
            #expect(categories.contains { $0.id == transaction.categoryId })
            #expect(stacks.contains { $0.transactionId == transaction.id })
        }
        #expect(!stacks.isEmpty)
    }
}

/// SchemaV1 앱(1ca72b6)이 만든 저장소 → SchemaV2
@MainActor
struct SchemaV2MigrationTests {
    private final class BundleToken {}

    private func copied(_ base: String) throws -> (store: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "v2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [base, base + "-wal", base + "-shm"] {
            let source = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil))
            try FileManager.default.copyItem(at: source, to: folder.appending(path: name))
        }
        return (folder.appending(path: base), folder)
    }

    private func open(_ url: URL, folder: URL) throws -> ModelContext {
        ModelContext(try Persistence.openContainer(
            at: url, backupsDirectory: folder.appending(path: "backups"),
            defaults: UserDefaults(suiteName: "tooktook.v2.\(UUID().uuidString)")!
        ))
    }

    @Test func v1StoreKeepsEveryRecordAndLink() throws {
        let (url, folder) = try copied("storeV1.store")
        let context = try open(url, folder: folder)
        let stacks = try context.fetch(FetchDescriptor<Stack>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())

        #expect(stacks.count == 5)
        #expect(transactions.count == 4)
        #expect(categories.count == 10)   // 시드 8 + 사용자 2, 새로 만든 것 없음

        for (index, id) in StoreV1Fixture.transactionIDs.enumerated() {
            let transaction = try #require(transactions.first { $0.id == id })
            #expect(transaction.amountKRW == Int64(1_000 * (index + 1)))
            let stack = try #require(stacks.first { $0.id == transaction.sourceStackId })
            #expect(stack.id == StoreV1Fixture.stackIDs[index])
            #expect(stack.transactionId == id)
            #expect(stack.createdAt == StoreV1Fixture.baseDate.addingTimeInterval(Double(index) * 600))
            #expect(stack.placeLabel == "테스트시 \(index)동")
            #expect(categories.contains { $0.id == transaction.categoryId })
        }
        let expectedCategoryOfTransaction = [StoreV1Fixture.defaultIDs[0], StoreV1Fixture.renamedCafeID,
                                             StoreV1Fixture.archivedMedicalID, StoreV1Fixture.userFoodID]
        #expect(StoreV1Fixture.transactionIDs.map { id in transactions.first { $0.id == id }?.categoryId } == expectedCategoryOfTransaction)
        #expect(transactions.first { $0.id == StoreV1Fixture.transactionIDs[0] }?.memo == "메모")
        let pending = try #require(stacks.first { $0.id == StoreV1Fixture.stackIDs[4] })
        #expect(pending.status == .pending)
        #expect(pending.isPossibleDuplicate)
    }

    @Test func seededDefaultsAreTaggedWithoutChangingTheirIDsOrUserEdits() throws {
        let (url, folder) = try copied("storeV1.store")
        let context = try open(url, folder: folder)
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        func category(_ id: UUID) -> ExpenseCategory? { categories.first { $0.id == id } }

        // 기존 ID 그대로, 시드와 같은 것에만 defaultKey
        #expect(category(StoreV1Fixture.defaultIDs[0])?.defaultKey == "food")
        #expect(category(StoreV1Fixture.defaultIDs[2])?.defaultKey == "transport")
        #expect(category(StoreV1Fixture.defaultIDs[7])?.defaultKey == "other")
        // 보관한 기본 카테고리: 표시는 붙고 보관 상태는 그대로
        #expect(category(StoreV1Fixture.archivedMedicalID)?.defaultKey == "medical")
        #expect(category(StoreV1Fixture.archivedMedicalID)?.isArchived == true)
        // 이름을 바꾼 기본 카테고리: 이름 유지, 확신할 수 없으므로 표시하지 않음
        #expect(category(StoreV1Fixture.renamedCafeID)?.name == "커피")
        #expect(category(StoreV1Fixture.renamedCafeID)?.defaultKey == nil)
        // 사용자가 만든 같은 이름 카테고리는 기본으로 잘못 묶지 않음
        #expect(category(StoreV1Fixture.userFoodID)?.defaultKey == nil)
        #expect(category(StoreV1Fixture.userDrinksID)?.defaultKey == nil)
        // 기본 카테고리 ID를 고정 UUID로 바꾸지 않음
        #expect(!categories.contains { category in DefaultCategory.all.contains { $0.fixedID == category.id } })
    }

    @Test func v0StoreMigratesThroughToV2() throws {
        let (url, folder) = try copied("default.store")
        let context = try open(url, folder: folder)
        #expect(try context.fetchCount(FetchDescriptor<Stack>()) == 5)
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 2)
        let archived = try #require(try context.fetch(FetchDescriptor<ExpenseCategory>()).first { $0.id == StoreFixture.archivedCategoryID })
        #expect(archived.isArchived)
        #expect(archived.defaultKey == nil)
    }

    @Test func migrationRunsOnceAndReopeningKeepsData() throws {
        let (url, folder) = try copied("storeV1.store")
        let defaults = UserDefaults(suiteName: "tooktook.v2.\(UUID().uuidString)")!
        let backups = folder.appending(path: "backups")
        let first = ModelContext(try Persistence.openContainer(at: url, backupsDirectory: backups, defaults: defaults))
        let newStack = try StackStore(context: first).createStack(source: .appIntent)

        let reopened = ModelContext(try Persistence.openContainer(at: url, backupsDirectory: backups, defaults: defaults))
        #expect(try reopened.fetchCount(FetchDescriptor<Stack>()) == 6)
        let ids = try reopened.fetch(FetchDescriptor<Stack>()).map(\.id)
        #expect(ids.contains(newStack.id))
        // 열기 전 사본은 V2 첫 실행 때 한 번만
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 1)
    }

    @Test func preMigrationCopyMatchesTheV1Original() throws {
        let (url, folder) = try copied("storeV1.store")
        let original = try Data(contentsOf: url)
        _ = try open(url, folder: folder)
        let backups = folder.appending(path: "backups")
        let copyFolder = try #require(try FileManager.default.contentsOfDirectory(atPath: backups.path).first)
        #expect(copyFolder.hasPrefix("before-2.0.0-"))
        #expect(try Data(contentsOf: backups.appending(path: copyFolder).appending(path: "storeV1.store")) == original)
    }

    /// 마이그레이션 단계가 중간에 실패하면 어떻게 되는지 실제로 확인한다.
    @Test func failedMigrationStepLeavesARestorableCopy() throws {
        let (url, folder) = try copied("storeV1.store")
        let backups = folder.appending(path: "backups")
        let originalHash = try Data(contentsOf: url)
        // 앱과 같은 순서: 열기 전 사본 → 열기(이번엔 실패하는 단계)
        let copy = try #require(try Persistence.copyStoreFiles(at: url, into: backups, label: "before-2.0.0"))

        struct StageFailed: Error {}
        enum FailingPlan: SchemaMigrationPlan {
            static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
            static var stages: [MigrationStage] {
                [.custom(fromVersion: SchemaV1.self, toVersion: SchemaV2.self, willMigrate: nil, didMigrate: { _ in throw StageFailed() })]
            }
        }
        let schema = Schema(versionedSchema: SchemaV2.self)
        #expect(throws: (any Error).self) {
            _ = try ModelContainer(for: schema, migrationPlan: FailingPlan.self,
                                   configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        }

        // 사본은 원본과 같고, V1 앱 그대로 다시 열 수 있다
        #expect(try Data(contentsOf: copy.appending(path: "storeV1.store")) == originalHash)
        let v1 = Schema(versionedSchema: SchemaV1.self)
        let restored = try ModelContainer(for: v1, configurations: ModelConfiguration(schema: v1, url: copy.appending(path: "storeV1.store"), cloudKitDatabase: .none))
        #expect(try ModelContext(restored).fetchCount(FetchDescriptor<SchemaV1.Stack>()) == 5)
        // 실제로 확인한 동작: 단계 후처리가 실패해도 Core Data는 스키마 변경을 이미 원본에 적용해 둔다.
        // 그래서 원본 보존은 '열기 전 사본'에 기댄다.
        #expect((try? Data(contentsOf: url)) != originalHash)

        // 다시 시도(앱 재실행)하면 바뀐 원본은 V2로 열리고 레코드는 그대로다. 실패한 후처리(기본 카테고리 표시)만 빠져 있다.
        let retried = ModelContext(try Persistence.openContainer(
            at: url, backupsDirectory: backups, defaults: UserDefaults(suiteName: "tooktook.v2.\(UUID().uuidString)")!
        ))
        #expect(try retried.fetchCount(FetchDescriptor<Stack>()) == 5)
        #expect(try retried.fetchCount(FetchDescriptor<LedgerTransaction>()) == 4)
        #expect(try retried.fetch(FetchDescriptor<ExpenseCategory>()).allSatisfy { $0.defaultKey == nil })
    }
}

/// 저장소를 열지 못할 때의 동작
@MainActor
struct StoreFailureTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func corruptedStoreFailsWithoutReplacingOrDeletingTheFile() throws {
        let dir = try folder()
        let storeURL = dir.appending(path: "default.store")
        let garbage = Data("this is not a sqlite database".utf8)
        try garbage.write(to: storeURL)

        let controller = StoreController(storeURL: storeURL, backupsDirectory: dir.appending(path: "backups"))

        guard case .failed = controller.state else {
            Issue.record("손상된 저장소가 열렸다")
            return
        }
        #expect(controller.container == nil)
        // 원본은 그대로, 새 저장소로 바꿔치기하지 않았다
        #expect(try Data(contentsOf: storeURL) == garbage)
        // 실패 당시 사본이 따로 보관됐다
        let preserved = try #require(controller.preservedCopy)
        #expect(try Data(contentsOf: preserved.appending(path: "default.store")) == garbage)
    }

    @Test func retryUsesSameFileAndRecoversWhenOpenStartsWorking() throws {
        let dir = try folder()
        var attempts = 0
        let schema = Schema(versionedSchema: SchemaV1.self)
        let controller = StoreController(storeURL: dir.appending(path: "default.store"), backupsDirectory: dir.appending(path: "backups")) {
            attempts += 1
            if attempts == 1 { throw CocoaError(.fileReadCorruptFile) }
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        #expect(controller.container == nil)

        controller.retry()
        #expect(controller.container != nil)
        #expect(attempts == 2)
    }

    @Test func intentFailsInsteadOfReportingSuccessWhenStoreIsUnavailable() throws {
        let dir = try folder()
        let controller = StoreController(storeURL: dir.appending(path: "default.store"), backupsDirectory: dir.appending(path: "backups")) {
            throw CocoaError(.fileReadCorruptFile)
        }
        #expect(throws: StoreUnavailableError.self) {
            _ = try CaptureStackIntent.saveStack(using: controller)
        }
    }

    @Test func intentSavesLocallyWithoutNetworkWork() throws {
        let dir = try folder()
        let storeURL = dir.appending(path: "default.store")
        let controller = StoreController(storeURL: storeURL, backupsDirectory: dir.appending(path: "backups")) {
            try Persistence.openContainer(at: storeURL, backupsDirectory: dir.appending(path: "backups"),
                                          defaults: UserDefaults(suiteName: "tooktook.intent.\(UUID().uuidString)")!)
        }

        // 위치·알림·지오코딩 없이 로컬 저장만으로 끝나는 단계
        let (stack, _) = try CaptureStackIntent.saveStack(using: controller)

        // 앱 재실행처럼 같은 파일을 새로 열어도 남아 있다
        let reopened = try Persistence.openContainer(at: storeURL, backupsDirectory: dir.appending(path: "backups"),
                                                     defaults: UserDefaults(suiteName: "tooktook.intent.\(UUID().uuidString)")!)
        let ids = try ModelContext(reopened).fetch(FetchDescriptor<Stack>()).map(\.id)
        #expect(ids.contains(stack.id))
    }
}
