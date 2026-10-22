# iCloud 동기화 아키텍처 (설계)

상태: 설계 문서. CloudKit은 아직 켜지 않았다(`cloudKitDatabase: .none`). 유료 Apple Developer Program 가입과 iCloud Capability 설정 이후 `docs/ICLOUD_MIGRATION_PLAN.md` 순서대로 진행한다.

표기: **[확인]** 이 저장소에서 테스트나 SDK로 확인한 사실 / **[가정]** Apple 문서·일반 지식에 기댄 것으로 실기기 검증이 필요한 것.

## 1. 목표와 원칙
- 회원가입·로그인 없이 시작한다. Sign in with Apple, 자체 서버, 외부 BaaS는 쓰지 않는다.
- **로컬이 먼저다.** Back Tap 스택은 항상 로컬 SwiftData에 먼저 저장되고, 성공 판단은 로컬 저장 기준이다.
- iCloud를 쓸 수 있으면 사용자의 **CloudKit Private Database**에 동기화한다. 못 쓰면 로컬 가계부로 그대로 동작한다.
- iCloud 동기화는 백업이 아니다. 삭제·수정도 모든 기기로 퍼진다. JSON 백업은 독립적인 복구 수단으로 유지한다.
- 확실히 알 수 있는 것만 표시한다. 진행률이나 "동기화 완료"를 근거 없이 보여주지 않는다.

## 2. D-1. CloudKit 구성
| 항목 | 계획 |
|---|---|
| 데이터베이스 | CloudKit Private Database (사용자 본인만 접근) |
| 컨테이너 ID | `iCloud.com.twentyonestar.tooktook` (번들 ID와 맞춤, 한 번 만들면 삭제·이름 변경 불가) |
| Capability | Signing & Capabilities › iCloud › CloudKit 체크, 위 컨테이너 선택 / Background Modes › Remote notifications |
| SwiftData 설정 | `ModelConfiguration(schema:url:cloudKitDatabase: .private("iCloud.com.twentyonestar.tooktook"))` — 같은 `default.store` URL 유지 |
| 지원 버전 | SwiftData CloudKit 동기화는 iOS 17부터 **[확인: SDK의 `CloudKitDatabase` 가용성 iOS 17]** → 최소 지원 버전 변경 없음 |
| 환경 | 개발 빌드는 CloudKit Development 환경, TestFlight·App Store는 Production. 첫 출시 전 CloudKit Console에서 Development 스키마를 Production으로 배포해야 한다 **[가정]** |
| 스키마 생성 | Development 환경에 레코드 타입을 미리 만들려면 개발 빌드에서 한 번 동기화하거나 Core Data `initializeCloudKitSchema`를 쓰는 방법이 있다 **[가정, 검증 필요]** |

`.automatic`을 쓰지 않는다. 기본값은 iCloud 권한이 있으면 바로 동기화를 시작하므로, 켜는 시점을 코드로 통제할 수 없다 **[확인: SDK 기본값 `.automatic`]**.

## 3. 모델 요구사항과 현재 상태
CloudKit 동기화 모델은 unique 제약을 쓸 수 없고, 모든 속성이 옵셔널이거나 기본값이 있어야 하며, 관계는 옵셔널이고 역관계가 있어야 한다.

현재 `SchemaV1`의 위반 20건 **[확인: `CloudKitAudit` 테스트]**:
- unique: `Stack.id`, `LedgerTransaction.id`, `ExpenseCategory.id`
- 기본값 없는 필수 속성: Stack 6개(`id, createdAt, captureSourceRaw, statusRaw, locationStatusRaw, isPossibleDuplicate`), LedgerTransaction 6개(`id, amountKRW, categoryId, occurredAt, createdAt, updatedAt`), ExpenseCategory 5개(`id, name, symbol, displayOrder, isArchived`)
- 관계: 없음 (UUID 필드로만 연결하므로 관계 규칙·삭제 규칙 위반 없음)

**모델 수정이 필요하다.** 해결 방향(SchemaV2): unique 제거 + 각 필수 속성에 기본값. 이름·타입·의미는 그대로. 테스트 전용 후보로 V1 → V2 경량 마이그레이션이 레코드·값·UUID 연결을 모두 유지함을 확인했다 **[확인: `CandidateMigrationTests`]**. 영향받는 데이터: 세 모델 전부의 스키마 메타데이터. 저장된 값은 바뀌지 않는다.

### unique 제거의 결과
SwiftData가 더 이상 `id` 중복을 막지 않는다. 지금 코드에서 같은 `id`를 다시 넣는 경로는 백업 가져오기뿐이며, 가져오기는 기존 레코드를 모두 지운 뒤 넣으므로 한 기기 안에서는 중복이 생기지 않는다. 기기 사이 중복은 4절에서 다룬다.

## 4. D-2. 기존 데이터와 여러 기기
| 위험 | 원인 | 대응 |
|---|---|---|
| 기존 데이터가 빈 DB로 교체 | 저장소 URL을 바꾸거나 새 컨테이너를 만들 때 | **같은 `default.store`를 그대로 연다.** 열기 실패 시 빈 저장소를 만들지 않는 현재 정책 유지(StoreController) |
| 로컬 + 클라우드 중복 | 한 사용자가 기기 두 대에서 각자 쓰다가 둘 다 동기화를 켬 | 스택·지출은 UUID가 서로 다르므로 실제로 다른 기록이다(중복 아님). 문제는 기본 카테고리(아래) |
| **기본 카테고리 중복** | 각 기기가 첫 실행 때 `UUID()`로 기본 8개를 만든다. 두 기기를 합치면 "식비"가 2개 | V2에서 기본 카테고리에 **고정 UUID**를 쓰고, 기존 설치본은 동기화 시작 전 "이름이 같은 기본 카테고리"를 하나로 합치는 정리 단계(지출의 `categoryId`를 대표 ID로 바꿈)를 둔다 |
| 같은 UUID 충돌 | unique 제거 후 같은 `id`가 두 레코드로 존재 | 정상 경로에서는 생기지 않음. 생기면 앱이 `id` 기준 중복 정리(더 최근 `updatedAt` 유지)를 실행. 정리 함수는 테스트로 고정 |
| 여러 기기에서 동시에 만든 스택 | 기기마다 다른 UUID | 서로 다른 스택으로 모두 남는다. 앱의 "3초 중복 의심" 표시는 같은 기기 안의 연속 탭 판단용이며 CloudKit 레코드 중복과는 다른 개념 |
| 삭제된 기록 재등장 | 오프라인 기기가 오래된 데이터를 들고 다시 연결 | CloudKit 미러링은 삭제도 동기화하므로 일반적으로 재등장하지 않음 **[가정]**. 백업 가져오기는 "전체 삭제 후 삽입"이라 다른 기기에서도 삭제·재생성이 일어남 → 동기화 중에는 가져오기 전에 모든 기기에 반영된다는 경고 |
| 보관된 카테고리 | `isArchived`는 일반 속성 | 그대로 동기화된다. 보관 카테고리를 쓰는 지출도 정상 조회(현재 동작 유지) |
| 미정리 스택 ↔ 확정 지출 연결 | `Stack.transactionId`와 `LedgerTransaction.sourceStackId`가 서로를 UUID로 가리킨다 | 두 레코드가 다른 시점에 도착할 수 있다. 상대가 아직 없을 때 화면은 기존처럼 nil 안전하게 처리하고, 무결성 검사는 "상대가 끝내 없을 때"만 문제로 본다 |
| 새 iPhone에서 데이터 도착 전 빈 화면 | 가져오기는 비동기, 완료 시점을 SwiftData가 알려주지 않음 **[가정]** | 첫 실행에서 iCloud 계정이 있으면 "iCloud에서 기록을 가져오는 중일 수 있어요" 안내를 비어 있는 인박스에 표시. 이 상태에서는 기본 카테고리를 바로 만들지 않거나(고정 UUID라면 만들어도 무해) |

## 5. D-3. 오프라인 우선
- Back Tap → `CaptureStackIntent.saveStack` → 로컬 `context.save()` 성공 시 "남겼어요". 네트워크·CloudKit 호출 없음 **[확인: `intentSavesLocallyWithoutNetworkWork` 테스트]**.
- CloudKit 업로드는 시스템이 백그라운드에서 진행. 실패해도 로컬 레코드는 그대로 남고 다음 기회에 재시도 **[가정: NSPersistentCloudKitContainer 동작]**.
- 앱을 닫아도 로컬 기록은 유지(이미 확인된 현재 동작).
- 위치 역지오코딩과 마찬가지로, 동기화 상태는 스택 저장 성공 판단에 절대 끼어들지 않는다.

## 6. D-4. iCloud 계정 상태별 동작
상태 판단은 `CKContainer(identifier:).accountStatus()`와 `CKAccountChanged` 알림으로 한다.

| 상태 | 앱 동작 | 설정 표시 |
|---|---|---|
| 사용 가능 | 동기화 켬 | iCloud 사용 가능 |
| 미로그인 (`noAccount`) | 로컬만 사용. 기능 제한 없음 | 이 기기에만 저장 중 · iCloud에 로그인하면 동기화할 수 있어요 |
| 제한 (`restricted`) / 앱의 iCloud 사용 꺼짐 | 로컬만 | 이 기기에만 저장 중 · 설정에서 iCloud 사용을 허용해 주세요 |
| 판단 불가 (`couldNotDetermine`, `temporarilyUnavailable`) | 로컬 계속 사용, 다음 활성화 때 재확인 | 동기화 준비 중 |
| 네트워크 없음 | 로컬 저장 계속, 나중에 자동 재개 | 표시 변경 없음(계정 상태는 정상) |
| 저장 공간 부족 / 지속 오류 | 로컬 계속 | 동기화에 문제가 있어요 (오류를 실제로 관찰했을 때만) |
| 계정 변경·로그아웃 | **위험 구간.** NSPersistentCloudKitContainer는 계정이 바뀌면 이전 계정의 미러 데이터를 로컬에서 정리할 수 있다 **[가정, 반드시 실기기 검증]** | 계정이 바뀌었어요 안내 |
| 새 iPhone에서 다운로드 중 | 로컬 비어 있음 | 4절의 안내 |

계정 변경 대비: 동기화를 처음 켤 때와 계정 변경을 감지했을 때, 정리가 일어나기 전에 **로컬 JSON 스냅샷을 자동으로 남기는** 방안을 1순위로 검토한다.

## 7. Phase E. 동기화 UX
- 회원가입·로그인 화면·필수 계정 없음. 설정에 "iCloud 동기화" 섹션 하나만 둔다.
- 설명: "iCloud로 기록을 동기화하면 새로운 iPhone에서도 가계부를 이어서 사용할 수 있어요."
- 상태 문구: iCloud 사용 가능 / 동기화 준비 중 / iCloud 연결 필요 / 동기화에 문제가 있어요 / 이 기기에만 저장 중.
- **표시 근거**: 계정 상태는 CloudKit API로 확실히 알 수 있다. 개별 업로드 완료·진행률은 SwiftData가 공개 API로 주지 않으므로 표시하지 않는다. Core Data의 `NSPersistentCloudKitContainer.eventChangedNotification`이 SwiftData에서도 관찰되는지 확인되면 "마지막 동기화 이벤트 시각"만 보조로 쓴다 **[가정, 검증 필요]**. "백업 완료", "안전하게 저장됨" 같은 문구는 쓰지 않는다.
- **전환 UX**
  - 신규 설치: iCloud 사용 가능하면 처음부터 켬(로컬 데이터가 없으므로 중복·손실 위험 없음).
  - 기존 사용자 업데이트: 자동으로 켜지 않는다. 한 번 안내 → 동의하면 ① 로컬 JSON 스냅샷 자동 저장 ② 기본 카테고리 정리 ③ 동기화 시작. 거절하면 "이 기기에만 저장 중".
  - 끄기: 이 기기의 로컬 기록은 남기고 업로드만 멈춘다는 점, 다른 기기와 더 이상 맞춰지지 않는다는 점을 안내. 다시 켤 때의 재업로드·중복 동작은 검증 전까지 "다시 켜기"를 백업 후에만 허용한다 **[가정]**.
  - 동기화 중 백업 가져오기: "모든 기기의 기록이 이 파일 내용으로 바뀌어요" 경고를 추가.

## 8. 하지 않는 것 (이번 단계)
Sign in with Apple, 자체 서버, Firebase·Supabase, 자동 병합, App Group 이전, 잠금화면 위젯, JSON 백업 제거.
