# 툭툭 (tooktook)

결제할 때 iPhone 뒷면을 두 번 톡톡 두드려 지출 흔적(스택)만 남기고, 금액과 카테고리는 나중에 모아서 정리하는 iOS 가계부 앱.

- Swift / SwiftUI / SwiftData / App Intents / Swift Charts
- iOS 17.0+
- 외부 의존성 없음, 모든 데이터는 기기 로컬에 저장

## 구조

```
TookTook/
  App/        앱 진입점, 탭 라우팅, 알림 델리게이트
  Models/     Stack, LedgerTransaction(PRD의 Transaction), ExpenseCategory(PRD의 Category), 환경설정
  Services/   StackStore(쓰기 규칙), 위치, 정리 알림, 백업
  Intents/    CaptureStackIntent: 화면 없이 스택을 저장하는 App Intent + App Shortcut
  Views/      스택 인박스, 연속 정리, 내역, 통계, 설정, 카테고리 관리
```

Xcode 프로젝트는 폴더 동기화 그룹을 쓰므로 `TookTook/` 아래에 파일을 추가하면 자동으로 타깃에 포함된다.

## PRD 대응 메모

- **스택 생성 (FR-01)**: `CaptureStackIntent`는 `openAppWhenRun = false`. 스택을 먼저 저장하고(실패 시 오류를 던져 단축어에 실패로 표시), 그다음 위치를 붙인다(BR-03).
- **중복 (BR-10)**: 3초 안에 연속 생성된 스택은 지우지 않고 `isPossibleDuplicate`로 표시만 한다.
- **위치 (FR-02)**: 4초 타임아웃의 단발 요청. 권한 요청은 설정 화면에서만 한다. 주소는 앱이 활성화될 때 비동기로 붙이며 정확도 500m 초과면 생략, 100m 초과면 동 단위까지만, 상호명은 쓰지 않는다.
- **정리 알림 (FR-05)**: 다음 알림에는 정확한 미정리 건수를, 이후 6일치에는 건수 없는 폴백 문구를 예약한다. 스택 생성·정리 시 다시 예약한다.
- **합계 (BR-02, FR-07)**: 확정 지출은 `LedgerTransaction`만 합산한다. 미정리 스택은 따로 건수만 보여준다.

## 빌드

```bash
open TookTook.xcodeproj
```

시뮬레이터 런타임이 없으면 Xcode > Settings > Components에서 iOS 플랫폼을 설치한다.
