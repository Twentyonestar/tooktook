# App Store 출시 체크리스트 (툭툭가계부 1.0)

## 준비 완료 (코드·파일)
- [x] 앱 아이콘 1024×1024, 투명도 없음 (사용자가 만든 ₩ 아이콘, 2026-10-31 교체. `tools/make-temp-icon.swift`는 이전 임시 아이콘 생성기)
- [x] 개인정보 매니페스트 `TookTook/PrivacyInfo.xcprivacy`: 추적 없음, 수집 데이터 없음, UserDefaults(CA92.1)·파일 생성 날짜(C617.1) 사용 이유
- [x] 암호화 신고 `ITSAppUsesNonExemptEncryption = NO`
- [x] 버전 1.0 (1), 표시 이름 툭툭가계부, 카테고리 금융
- [x] Release 빌드 확인: 매니페스트 포함, 테스트 픽스처·디버그 라이브러리 없음, 예시 데이터 코드는 DEBUG 전용이라 배포 빌드에 들어가지 않음
- [x] 스크린샷 6.9인치(1320×2868) 4장 `docs/appstore/screenshots/`, 알파 채널 없음 (`tools/flatten-screenshots.swift`)
- [x] 개인정보 처리방침 `TookTook/Resources/PrivacyPolicy.md` (앱 설정 › 개인정보 처리방침에서 보임, 웹 게시용 원본도 이 파일)
- [x] 앱 설명·키워드·심사 메모 `docs/appstore/listing.md`
- [x] iCloud 동기화는 1.0에서 끔 (`cloudKitDatabase: .none`)
- [x] 출시 전 최종 점검 (2026-10-30): 위치 안내 문구를 실제 동작(Apple 지도 역지오코딩)에 맞춤, 차트 색 구분, 다크 모드·큰 글자 대응, Release 번들 확인

멤버십 활성화 이후 순서는 [RELEASE_RUNBOOK.md](RELEASE_RUNBOOK.md)를 따른다.

## 사용자가 할 일
1. [ ] 개발자 멤버십 활성화 확인 (developer.apple.com/account 에서 Pending이 사라질 때까지, 최대 48시간)
2. [ ] Xcode › Settings › Apple Accounts 에서 유료 팀이 보이는지 확인 → Claude에게 알리기
3. [ ] `TookTook/Resources/PrivacyPolicy.md` 마지막 줄에 문의 이메일을 적고, 노션 공개 페이지 등에 게시 → 주소를 Claude에게 알리기
4. [ ] App Store Connect에서 새 앱 만들기 (`listing.md`의 값 사용)
5. [ ] 업로드된 빌드를 TestFlight로 받아 실기기 확인
6. [ ] 심사 제출

## 유료 팀이 활성화되면 Claude가 할 일
1. 서명 팀을 유료 팀 ID로 변경
2. Archive → App Store Connect 업로드
3. TestFlight 확인 항목 안내 (뒷면 탭, 알림, 위치)

## 다시 스크린샷을 찍을 때
```
xcrun simctl status_bar <iPhone 17 Pro Max ID> override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl launch <ID> com.twentyonestar.tooktook -TookTookDemo
```
`-TookTookDemo`는 DEBUG 빌드에서만, 기록이 없는 저장소에만 예시 데이터를 넣는다.
실제 기록이 있는 iPhone에서 찍을 때는 `-TookTookDemo -TookTookDemoSeparateStore`로 실행한다. 기본 저장소 대신 `Application Support/DemoScreenshots/demo.store`를 쓰고, 설정값과 알림 예약을 바꾸지 않는다. 일반 실행으로 돌아가면 실제 기록이 보인다.
```
xcrun devicectl device process launch --device <기기 ID> --terminate-existing com.twentyonestar.tooktook -- -TookTookDemo -TookTookDemoSeparateStore
```
찍은 뒤 `xcrun swift tools/flatten-screenshots.swift docs/appstore/screenshots/*.png`로 알파 채널을 없앤다.
