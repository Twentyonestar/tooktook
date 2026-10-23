# iCloud 동기화 활성화 절차

전제: `docs/ICLOUD_SYNC_ARCHITECTURE.md`. 각 단계는 앞 단계의 검증이 끝나야 진행한다. 데이터 손실 가능성이 확인되면 그 단계에서 멈추고 보고한다.

## 0. 선행 조건 (현재 미충족)
- [ ] 유료 Apple Developer Program 가입 (개인 무료 팀은 iCloud Capability 사용 불가)
- [ ] 같은 iCloud 계정의 실기기 2대 이상 (동기화 검증용)
- [ ] 테스트용 iCloud 계정 1개 (실사용 계정 데이터 보호)

## 1. SchemaV2 출시 (CloudKit은 계속 꺼둠)
CloudKit 호환 모델만 먼저 배포해서, 동기화와 스키마 변경 위험을 분리한다.
1. `SchemaV2`: `id`의 unique 제거, 필수 속성 기본값 추가. 테스트 전용 `SchemaV2Candidate`와 같은 내용으로 앱에 옮긴다.
2. 기본 카테고리 고정 UUID 도입. 기존 설치본은 V1 → V2 사이 `.custom` 단계 또는 앱 시작 정리 작업으로 "이름이 같은 기본 카테고리" 병합(지출 `categoryId` 재지정, 남는 카테고리는 보관 처리로 두고 삭제하지 않음).
3. `id` 기준 중복 정리 함수와 테스트 (unique가 사라졌으므로).
4. 검증
   - StoreV0, StoreV1 픽스처 → V2 마이그레이션 테스트
   - 실기기 저장소 사본 → V2 (`TOOKTOOK_EXTERNAL_STORE_DIR`)
   - `CloudKitAudit`에서 V2 위반 0건
   - 실기기 설치 후 기기 DB 비교(스택·지출·카테고리 ID와 값 동일), `StoreBackups/before-2.0.0-*` 생성 확인
5. 이 버전이 실제 사용자에게 충분히 배포된 뒤 2단계로 간다.

## 2. CloudKit 연결 (개발 환경)
1. Xcode: iCloud(CloudKit) + 컨테이너 `iCloud.com.twentyonestar.tooktook`, Background Modes › Remote notifications.
2. 코드: 동기화 켜기 여부를 결정하는 단일 지점(`Persistence.openContainer`)에서만 `cloudKitDatabase: .private(...)` 사용. 기본은 여전히 `.none`.
3. 개발 빌드 + 테스트 계정으로 레코드 타입 생성 확인(CloudKit Console Development).
4. 검증 (테스트 계정, 기기 2대)
   - 기기 A에서 스택 생성 → 기기 B에 도착
   - 비행기 모드에서 생성 → 복구 후 도착
   - 기기 A 삭제 → 기기 B에서 사라짐, 재등장 없음
   - 보관 카테고리, 스택↔지출 연결 유지
   - 새 기기(빈 상태)에서 첫 실행 → 기록 도착까지의 화면, 기본 카테고리 중복 여부
   - **iCloud 로그아웃·계정 변경 시 로컬 데이터 처리** — 데이터가 사라지면 이 단계에서 중단하고 대비책(자동 JSON 스냅샷) 먼저 구현
   - 백업 가져오기가 다른 기기에 퍼지는 모습

## 3. 기존 사용자 전환 UX
1. 업데이트 후 자동 활성화하지 않는다.
2. 설정 "iCloud 동기화" 안내에서 사용자가 켜면: 로컬 JSON 스냅샷 자동 저장(앱 내부 보관) → 기본 카테고리 정리 → 동기화 시작.
3. 상태 표시는 계정 상태 기반만. 진행률·완료 표시 없음.
4. 신규 설치는 iCloud 사용 가능 시 처음부터 켬.

## 4. Production 배포
1. CloudKit Console에서 Development 스키마를 Production으로 배포.
2. TestFlight(Production 환경)로 2단계 검증을 다시 수행.
3. App Store 개인정보 고지에 iCloud 동기화(사용자 본인의 iCloud에 저장) 반영.

## 5. 되돌리기
- 동기화에 문제가 있으면 코드에서 `cloudKitDatabase: .none`으로 되돌린 업데이트를 낸다. 로컬 저장소는 같은 파일이므로 기록은 기기에 남는다 **[가정, 2단계에서 확인]**.
- 스키마는 되돌리지 않는다(V2 유지). V2는 CloudKit 없이도 정상 동작한다.

## 현재 진행 상황
| 단계 | 상태 |
|---|---|
| SchemaV1 + 마이그레이션 계획, 열기 전 사본, 열기 실패 처리 | 완료 (9261502) |
| CloudKit 호환성 점검 | 완료 (a65d62d), V2 위반 0건 (20f054f) |
| 1. SchemaV2 (CloudKit 호환 모델, 기본 카테고리 고정 ID·병합, ID 중복 정책) | 코드·테스트 완료 (20f054f). 실기기 설치 검증은 아래 기록 |
| 2~4. CloudKit 연결·전환·배포 | 미착수 (유료 계정 필요) |
| 실기기 동기화 검증 | 미검증 |
