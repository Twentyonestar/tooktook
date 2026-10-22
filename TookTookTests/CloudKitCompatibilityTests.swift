import Foundation
import SwiftData
import Testing
@testable import TookTook

/// SwiftData + CloudKit이 요구하는 모델 조건을 스키마에서 직접 읽어 점검한다.
/// - 속성: unique 금지, 모든 속성은 옵셔널이거나 기본값이 있어야 함
/// - 관계: 옵셔널이어야 하고 역관계가 있어야 함
enum CloudKitAudit {
    struct Issue: Hashable, CustomStringConvertible {
        let entity: String
        let property: String
        let reason: String
        var description: String { "\(entity).\(property): \(reason)" }
    }

    static func issues(in schema: Schema) -> Set<Issue> {
        var found: Set<Issue> = []
        for entity in schema.entities {
            for constraint in entity.uniquenessConstraints {
                found.insert(Issue(entity: entity.name, property: constraint.joined(separator: "+"), reason: "unique"))
            }
            for attribute in entity.attributes {
                if attribute.isUnique {
                    found.insert(Issue(entity: entity.name, property: attribute.name, reason: "unique"))
                }
                if !attribute.isOptional && attribute.defaultValue == nil {
                    found.insert(Issue(entity: entity.name, property: attribute.name, reason: "required-without-default"))
                }
            }
            for relationship in entity.relationships {
                if !relationship.isOptional {
                    found.insert(Issue(entity: entity.name, property: relationship.name, reason: "required-relationship"))
                }
                if relationship.inverseName == nil {
                    found.insert(Issue(entity: entity.name, property: relationship.name, reason: "no-inverse"))
                }
            }
        }
        return found
    }
}

/// 테스트 전용 SchemaV2 후보. CloudKit 조건을 맞추려면 무엇을 바꿔야 하는지와
/// 그 변경이 기존 데이터를 잃지 않는 경량 마이그레이션인지 확인하기 위한 것이다. 앱에는 들어가지 않는다.
/// 변경: id의 unique 제거, 모든 필수 속성에 기본값. 필드 이름·타입·의미는 그대로.
enum SchemaV2Candidate: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Stack.self, LedgerTransaction.self, ExpenseCategory.self] }

    @Model final class Stack {
        var id: UUID = UUID()
        var createdAt: Date = Date.distantPast
        var captureSourceRaw: String = "appIntent"
        var statusRaw: String = "pending"
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracy: Double?
        var locationStatusRaw: String = "notRequested"
        var placeLabel: String?
        var completedAt: Date?
        var transactionId: UUID?
        var discardedAt: Date?
        var isPossibleDuplicate: Bool = false
        var placeLookupAttempts: Int = 0
        var placeLabelVersion: Int = 0
        init() {}
    }

    @Model final class LedgerTransaction {
        var id: UUID = UUID()
        var sourceStackId: UUID?
        var amountKRW: Int64 = 0
        var categoryId: UUID = UUID()
        var occurredAt: Date = Date.distantPast
        var memo: String?
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        init() {}
    }

    @Model final class ExpenseCategory {
        var id: UUID = UUID()
        var name: String = ""
        var symbol: String = "ellipsis.circle.fill"
        var displayOrder: Int = 0
        var isArchived: Bool = false
        init() {}
    }
}

enum CandidateMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2Candidate.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2Candidate.self)]
    }
}

struct CloudKitCompatibilityTests {
    /// 현재 스키마는 CloudKit과 호환되지 않는다. 목록이 바뀌면 문서(ICLOUD_SYNC_ARCHITECTURE.md)도 함께 고친다.
    @Test func schemaV1IsNotCloudKitCompatibleForDocumentedReasons() {
        let issues = CloudKitAudit.issues(in: Schema(versionedSchema: SchemaV1.self))
        let uniqueIDs: Set<CloudKitAudit.Issue> = [
            CloudKitAudit.Issue(entity: "Stack", property: "id", reason: "unique"),
            CloudKitAudit.Issue(entity: "LedgerTransaction", property: "id", reason: "unique"),
            CloudKitAudit.Issue(entity: "ExpenseCategory", property: "id", reason: "unique"),
        ]
        let expected = uniqueIDs.union(
            ["id", "createdAt", "captureSourceRaw", "statusRaw", "locationStatusRaw", "isPossibleDuplicate"]
                .map { CloudKitAudit.Issue(entity: "Stack", property: $0, reason: "required-without-default") }
        ).union(
            ["id", "amountKRW", "categoryId", "occurredAt", "createdAt", "updatedAt"]
                .map { CloudKitAudit.Issue(entity: "LedgerTransaction", property: $0, reason: "required-without-default") }
        ).union(
            ["id", "name", "symbol", "displayOrder", "isArchived"]
                .map { CloudKitAudit.Issue(entity: "ExpenseCategory", property: $0, reason: "required-without-default") }
        )
        #expect(issues == expected)
    }

    @Test func candidateV2SatisfiesCloudKitRules() {
        #expect(CloudKitAudit.issues(in: Schema(versionedSchema: SchemaV2Candidate.self)).isEmpty)
    }
}

/// V1 픽스처를 V2 후보로 경량 마이그레이션해 데이터가 그대로인지 확인한다.
@MainActor
struct CandidateMigrationTests {
    private final class BundleToken {}

    @Test func v1StoreMigratesToCandidateWithoutLoss() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "v2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let source = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil))
            try FileManager.default.copyItem(at: source, to: folder.appending(path: name))
        }
        let url = folder.appending(path: "default.store")

        // 현재 앱처럼 V1로 한 번 연 뒤
        _ = try Persistence.openContainer(at: url, backupsDirectory: folder.appending(path: "backups"),
                                          defaults: UserDefaults(suiteName: "tooktook.v2.\(UUID().uuidString)")!)

        // V2 후보로 연다
        let schema = Schema(versionedSchema: SchemaV2Candidate.self)
        let container = try ModelContainer(
            for: schema, migrationPlan: CandidateMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let stacks = try context.fetch(FetchDescriptor<SchemaV2Candidate.Stack>())
        let transactions = try context.fetch(FetchDescriptor<SchemaV2Candidate.LedgerTransaction>())
        let categories = try context.fetch(FetchDescriptor<SchemaV2Candidate.ExpenseCategory>())

        #expect(stacks.count == 5)
        #expect(transactions.count == 2)
        #expect(categories.count == 2)
        let completed = try #require(stacks.first { $0.id == StoreFixture.completedStackID })
        #expect(completed.createdAt == StoreFixture.baseDate)
        #expect(completed.statusRaw == "completed")
        #expect(completed.placeLabel == "테스트시 테스트구 테스트동")
        #expect(completed.transactionId == StoreFixture.foodTransactionID)
        let food = try #require(transactions.first { $0.id == StoreFixture.foodTransactionID })
        #expect(food.amountKRW == 12_500)
        #expect(food.categoryId == StoreFixture.foodCategoryID)
        #expect(food.sourceStackId == StoreFixture.completedStackID)
        #expect(categories.first { $0.id == StoreFixture.archivedCategoryID }?.isArchived == true)
        // 기본값으로 덮어쓴 값이 없는지
        #expect(!stacks.contains { $0.createdAt == Date.distantPast })
        #expect(!transactions.contains { $0.amountKRW == 0 })
    }
}
