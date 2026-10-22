# SwiftData 마이그레이션 계획

상태: 계획만 작성. 이번 작업에서는 스키마를 바꾸지 않았다.

## 1. 현재 모델 구조

`Persistence.container`가 `Schema([Stack, LedgerTransaction, ExpenseCategory])`로 기본 위치(`Application Support/default.store`)에 저장소 하나를 연다. `VersionedSchema`나 `SchemaMigrationPlan`은 없다.

| 모델 | 속성 | 비고 |
|---|---|---|
| Stack | `id`(unique), `createdAt`, `captureSourceRaw`, `statusRaw`, `latitude?`, `longitude?`, `horizontalAccuracy?`, `locationStatusRaw`, `placeLabel?`, `completedAt?`, `transactionId?`, `discardedAt?`, `isPossibleDuplicate`, `placeLookupAttempts = 0`, `placeLabelVersion = 0` | enum은 raw String으로 저장 |
| LedgerTransaction | `id`(unique), `sourceStackId?`, `amountKRW`(Int64), `categoryId`, `occurredAt`, `memo?`, `createdAt`, `updatedAt` | |
| ExpenseCategory | `id`(unique), `name`, `symbol`, `displayOrder`, `isArchived` | 삭제하지 않고 보관 |

모델 사이에 SwiftData `@Relationship`은 없다. 스택↔지출↔카테고리는 UUID로만 연결되어 있어서, 관계 삭제 규칙이나 역참조로 생기는 마이그레이션 위험은 없다. 대신 무결성은 앱 코드(StackStore, BackupService.validate)가 지킨다.

## 2. 지금까지의 변경 이력

- e622360: Stack에 `placeLookupAttempts`, `placeLabelVersion`을 기본값과 함께 추가했다. SwiftData 자동 경량 마이그레이션으로 처리됐고, 실기기의 기존 스택·지출이 보존되는 것을 기기 DB로 확인했다.

## 3. 스키마 변경 시 위험

| 변경 | 자동 마이그레이션 | 위험 |
|---|---|---|
| 기본값 있는 속성 추가 | 됨 | 낮음 |
| 옵셔널 속성 추가 | 됨 | 낮음 |
| 속성 이름 변경 | 안 됨 | `@Attribute(originalName:)` 없이 바꾸면 기존 값이 사라진다 |
| 타입 변경 (예: Int64 → Decimal) | 안 됨 | 저장소 열기 실패 → 현재 코드는 `fatalError`로 앱이 시작되지 않는다 |
| 옵셔널 → 필수 | 안 됨 | 기존 nil 값 때문에 실패 |
| unique 제약 추가 | 위험 | 기존 중복 데이터가 있으면 실패 |
| 모델 이름 변경·삭제 | 안 됨 | 데이터 손실 |
| raw String 값 변경 (예: `pending` → `open`) | 스키마는 그대로 | 기존 행이 기본값으로 해석돼 상태가 틀어진다. 커스텀 마이그레이션 필요 |
| App Group 저장소로 이동 (잠금화면 컨트롤용) | 해당 없음 | 파일을 옮기는 1회 작업이 필요하다. 실패하면 빈 저장소로 시작할 수 있다 |
| CloudKit 동기화 도입 | 해당 없음 | unique 제약 불가, 모든 속성이 옵셔널이거나 기본값 필요 |

가장 큰 위험은 저장소를 열지 못했을 때 `Persistence.container`가 `fatalError`로 끝나는 것이다. 업데이트 한 번으로 앱이 실행되지 않게 될 수 있다.

## 4. VersionedSchema / SchemaMigrationPlan 도입 계획

App Store 첫 출시 **전에** 도입한다. 출시 후에는 V1이 실제로 배포된 스키마와 정확히 같아야 하므로, 늦을수록 맞추기 어렵다.

1. `SchemaV1: VersionedSchema`를 만들고 현재 세 모델을 그 안으로 옮긴다. 속성·기본값·unique는 지금과 완전히 같게 한다. 앱 코드는 `typealias Stack = SchemaV1.Stack`처럼 별칭으로 그대로 쓴다.
2. `TookTookMigrationPlan: SchemaMigrationPlan`에 `schemas = [SchemaV1.self]`, `stages = []`로 시작한다.
3. `ModelContainer(for:migrationPlan:configurations:)`로 연다.
4. 다음 스키마 변경부터 `SchemaV2`를 추가하고, 경량이면 `.lightweight(fromVersion:toVersion:)`, 값 변환이 필요하면 `.custom(... willMigrate:didMigrate:)`를 단계로 둔다.
5. 각 버전마다 이전 버전 저장소 파일(테스트 리소스)을 열어 마이그레이션하는 단위 테스트를 둔다.

## 5. 기존 설치 데이터 호환

- V1은 현재 설치본의 스키마와 같아야 한다. 도입 직후 실기기에 덮어 설치해 기존 스택·지출이 그대로인지 기기 DB로 확인한다.
- 저장소 열기 실패 시 `fatalError` 대신: 기존 파일을 `default.store.broken-<날짜>`로 옮겨 보존하고, 사용자에게 알린 뒤 JSON 백업 가져오기를 안내한다. 데이터를 조용히 지우지 않는다.
- 마이그레이션이 들어가는 업데이트 전에는 앱에서 JSON 백업 내보내기를 권하는 안내를 띄운다.
- JSON 백업은 스키마와 별개로 `BackupPayload.version`을 유지한다. 새 필드는 옵셔널로 추가해 이전 백업 파일도 계속 읽는다(현재 방식).

## 6. 이번 작업에서 바꾸지 않은 이유

현재 출시 전이고 설치된 기기가 하나뿐이며, 계획한 다음 변경(잠금화면 컨트롤용 App Group 이동)은 유료 개발자 계정이 필요해 시점이 정해지지 않았다. 지금 스키마를 옮기면 위험만 생기고 얻는 것이 없어서, 출시 준비 단계에서 1번부터 진행하는 것을 권한다.
