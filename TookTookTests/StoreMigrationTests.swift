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
    private func copiedFixtureStore() throws -> (store: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            try FileManager.default.copyItem(at: try fixtureURL(name), to: folder.appending(path: name))
        }
        return (folder.appending(path: "default.store"), folder)
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
        for transaction in transactions {
            #expect(categories.contains { $0.id == transaction.categoryId })
            #expect(stacks.contains { $0.transactionId == transaction.id })
        }
        #expect(!stacks.isEmpty)
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
