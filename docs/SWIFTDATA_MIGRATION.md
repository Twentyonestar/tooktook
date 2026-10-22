# SwiftData 스키마 버전 관리와 마이그레이션

상태: SchemaV1 + 마이그레이션 계획 도입 완료 (커밋 9261502). CloudKit은 꺼져 있음.

## 1. 현재 구조

### 저장소
- 위치: `Library/Application Support/default.store` (+ `-wal`, `-shm`). 버전 관리 도입 전과 같은 파일을 그대로 연다.
- 여는 곳: `Persistence.openContainer` 한 곳. 앱과 App Intent 모두 `StoreController.shared`를 통해 같은 컨테이너를 쓴다. App Intent는 앱 프로세스에서 실행되며 별도 확장(Extension)이나 App Group 저장소는 없다.
- 옵션: `ModelConfiguration(schema:url:cloudKitDatabase: .none)`. CloudKit은 명시적으로 끈다(아래 4절).

### 모델 (`SchemaV1`, 1.0.0)
| 모델 | 속성 | 비고 |
|---|---|---|
| Stack | `id`(unique), `createdAt`, `captureSourceRaw`, `statusRaw`, `latitude?`, `longitude?`, `horizontalAccuracy?`, `locationStatusRaw`, `placeLabel?`, `completedAt?`, `transactionId?`, `discardedAt?`, `isPossibleDuplicate`, `placeLookupAttempts = 0`, `placeLabelVersion = 0` | enum은 raw String |
| LedgerTransaction | `id`(unique), `sourceStackId?`, `amountKRW`(Int64), `categoryId`, `occurredAt`, `memo?`, `createdAt`, `updatedAt` | |
| ExpenseCategory | `id`(unique), `name`, `symbol`, `displayOrder`, `isArchived` | 삭제 대신 보관 |

- SwiftData `@Relationship` 없음. 스택↔지출↔카테고리는 UUID 필드로만 연결되고, 무결성은 `StackStore`와 `BackupService.validate`가 지킨다.
- 앱 코드는 `typealias Stack = SchemaV1.Stack`처럼 별칭으로 현재 버전 모델을 쓴다.

### UserDefaults (SwiftData 밖)
`reminderEnabled`, `reminderMinutes`, `locationCaptureEnabled`, `appearance`, `hasCompletedOnboarding`, `storeSchemaVersion`(마지막으로 연 스키마 버전).

### JSON 백업
`BackupPayload.version = 1`. 이후 추가된 필드(`placeLookupAttempts`, `placeLabelVersion`)는 옵셔널이라 이전 파일도 읽는다(테스트 있음). 가져오기는 전체 교체.

## 2. 도입 과정에서 지킨 것
1. **픽스처 먼저**: 버전 관리 이전 모델(커밋 648696e)로 합성 데이터 저장소를 만들어 `TookTookTests/Fixtures/StoreV0`에 커밋(b0e213e)한 뒤에 코드를 바꿨다.
2. **같은 스키마**: 필드·기본값·unique를 하나도 바꾸지 않고 클래스만 `SchemaV1` 안으로 옮겼다. 그래서 기존 저장소는 마이그레이션 없이 열린다.
3. **검증**
   - 픽스처 사본을 새 코드로 열어 모든 레코드·필드·UUID 연결 확인, 원본 픽스처 해시 불변 확인
   - 실기기 저장소 **사본**(스택 17·지출 6·카테고리 8, a668d7a가 기록)을 새 코드로 열어 확인. 개인 데이터라 커밋하지 않고 `TOOKTOOK_EXTERNAL_STORE_DIR`로만 실행
   - 다시 열기(앱 재실행)와 쓰기 후 유지 확인
4. **열기 전 사본**: `storeSchemaVersion`이 현재 버전과 다르면(버전 관리 이전 설치본의 첫 실행 포함) 열기 전에 저장소 파일을 `Application Support/StoreBackups/before-<버전>-<시각>/`에 복사한다. 원본은 옮기지 않는다. 같은 종류 사본은 최근 3개만 남긴다.

## 3. 열기 실패 처리
- `fatalError` 제거. 실패하면 `StoreController.state = .failed`가 되고 앱은 "기록을 불러오지 못했어요" 화면을 보여준다(다시 시도하기, 복구 방법 확인하기). 원본을 지우는 버튼은 없다.
- 실패 시 빈 저장소를 만들지 않는다. 실패한 파일은 `StoreBackups/failed-open-<시각>/`에 사본을 남긴다.
- 다시 시도는 같은 파일을 다시 연다. 시뮬레이터에서 손상 파일 → 복구 화면 → 파일 복원 후 다시 시도 → 정상 화면을 확인했다.
- App Intent는 저장소가 없으면 `StoreUnavailableError`를 던져 단축어에 실패로 표시한다(성공 문구를 보여주지 않음).
- Core Data는 손상 파일에 대해 "Attempting recovery"를 로그로 남기지만, 테스트에서 파일 내용이 바뀌지 않음을 확인했다.

## 4. 변경 시 위험
| 변경 | 자동 마이그레이션 | 대응 |
|---|---|---|
| 기본값 있는 속성 추가 / 옵셔널 추가 | 경량 | SchemaV2 + `.lightweight` |
| unique 제거, 필수 속성에 기본값 추가 | 경량 (테스트로 확인, 5절) | 같음 |
| 속성 이름 변경 | 안 됨 | `@Attribute(originalName:)` |
| 타입 변경, 옵셔널 → 필수 | 안 됨 | `.custom` 단계에서 값 변환 |
| raw String 값 변경 | 스키마는 같음 | `.custom` 단계에서 값 갱신 |
| 모델 이름 변경·삭제 | 안 됨 | 새 모델 + 복사 단계 |
| `cloudKitDatabase` 기본값(.automatic) 방치 | – | iCloud 권한이 생기는 순간 검증 안 된 모델로 동기화 시작. `.none` 명시로 차단함 |

## 5. 다음 버전 추가 절차
1. `SchemaV2: VersionedSchema`를 만들고 모델을 복사해 바꾼다. `typealias`를 V2로 옮긴다.
2. `TookTookMigrationPlan.schemas`에 V2를 붙이고 `stages`에 단계를 추가한다.
3. `Persistence.openContainer`의 `Schema(versionedSchema:)`와 `currentSchemaVersion`을 V2로 바꾼다. 버전 표식이 달라지므로 첫 실행 때 자동으로 열기 전 사본이 생긴다.
4. 그 시점의 V1 저장소를 새 픽스처(StoreV1)로 남기고, V0·V1 픽스처 둘 다 V2로 여는 테스트를 추가한다.
5. 실기기 저장소 사본으로 `TOOKTOOK_EXTERNAL_STORE_DIR` 테스트를 실행한 뒤에만 기기에 설치한다.

CloudKit용 V2 후보(unique 제거 + 기본값)는 `TookTookTests/CloudKitCompatibilityTests.swift`의 `SchemaV2Candidate`로 이미 경량 마이그레이션이 무손실임을 확인했다. 실제 도입은 `docs/ICLOUD_MIGRATION_PLAN.md`를 따른다.
