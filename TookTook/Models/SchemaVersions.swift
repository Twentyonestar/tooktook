import SwiftData

/// 버전 관리를 도입하기 전(커밋 648696e까지)과 1ca72b6까지 배포된 스키마. 정의는 SchemaV1Models.swift에 고정돼 있다.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Stack.self, LedgerTransaction.self, ExpenseCategory.self]
    }
}

/// CloudKit 호환 스키마. V1에서 unique를 없애고 필수 속성에 기본값을 주었으며,
/// ExpenseCategory.defaultKey(옵셔널)를 추가했다. 속성 이름·타입은 V1과 같다.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Stack.self, LedgerTransaction.self, ExpenseCategory.self]
    }
}

/// 버전 사이 이동 경로. 새 스키마를 추가하면 schemas 끝에 붙이고 단계를 정의한다.
enum TookTookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// 스키마 변경은 경량(unique 제거·기본값·옵셔널 속성 추가). 끝난 뒤 시드로 만든 기본 카테고리에 defaultKey를 붙인다.
    /// 레코드의 ID·값은 바꾸지 않는다.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            DefaultCategory.tagSeededDefaults(in: try context.fetch(FetchDescriptor<SchemaV2.ExpenseCategory>()))
            try context.save()
        }
    )
}
