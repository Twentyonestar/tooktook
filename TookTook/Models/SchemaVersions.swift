import SwiftData

/// 버전 관리를 도입하기 전(커밋 648696e까지)에 배포된 모델과 **완전히 같은** 스키마.
/// 필드·기본값·unique를 바꾸면 기존 저장소가 열리지 않을 수 있으므로, 바꿀 때는 SchemaV2를 새로 만든다.
/// 호환성은 TookTookTests/Fixtures/StoreV0(버전 관리 이전 앱이 만든 저장소)로 검증한다.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Stack.self, LedgerTransaction.self, ExpenseCategory.self]
    }
}

/// 버전 사이 이동 경로. 새 스키마를 추가하면 schemas 끝에 붙이고 단계를 정의한다.
enum TookTookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
