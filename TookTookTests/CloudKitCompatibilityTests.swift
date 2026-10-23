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

    @Test func schemaV2SatisfiesCloudKitRules() {
        #expect(CloudKitAudit.issues(in: Schema(versionedSchema: SchemaV2.self)).isEmpty)
    }

    @Test func appUsesSchemaV2() {
        #expect(Persistence.currentSchemaVersion == "2.0.0")
    }
}
