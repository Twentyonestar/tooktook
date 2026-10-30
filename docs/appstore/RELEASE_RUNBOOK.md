# 출시 런북: 멤버십 활성화 이후 (툭툭가계부 1.0)

유료 개발자 멤버십이 활성화된 뒤 Archive → TestFlight → 심사 제출까지의 순서다.
멤버십이 활성화되기 전에는 서명·업로드를 하지 않는다. 그 전에 할 수 있는 점검은 아래 0~2단계에 있으며 이미 통과했다(2026-10-30).

## 0. 시작 조건
- [ ] developer.apple.com/account 에서 멤버십 상태가 Pending이 아님
- [ ] Xcode › Settings › Apple Accounts 에 유료 팀(개인 이름 + "Apple Developer Program")이 보임
- [ ] 이 팀의 Team ID(10자리)를 확인. Membership details 페이지에 있다.

## 1. 공개 페이지와 출시 전 빈칸
처리방침·지원 페이지는 GitHub Pages로 게시한다.
- 원본
  - 처리방침: `TookTook/Resources/PrivacyPolicy.md` (앱 번들과 같은 파일)
  - 지원: `site/support.md`
  - 첫 화면: `site/index.md`
- 빌드: `python3 tools/build_site.py`로 `_site/`를 만든다. 로컬 미리보기도 이 명령이다.
- 배포: `.github/workflows/pages.yml`이 위 파일이 바뀌어 푸시될 때마다 자동으로 게시한다.
- 최초 1회: 저장소 Settings › Pages › Build and deployment › Source를 **GitHub Actions**로 바꾼 뒤 Actions › Pages › Run workflow를 실행한다.

| 주소 | 용도 |
|---|---|
| https://twentyonestar.github.io/tooktook/privacy/ | App Store Connect 개인정보 처리방침 URL, `AppLinks.privacyPolicyURL` |
| https://twentyonestar.github.io/tooktook/support/ | App Store Connect 지원 URL, `AppLinks.supportURL` |

두 주소는 실제로 HTTPS로 열리는 것을 확인한 뒤에만 앱에 넣는다. 넣으면 `ReleaseContentTests`의 주소 테스트도 같이 바꾼다.

| 빈칸 | 위치 | 지금 상태 |
|---|---|---|
| 문의 이메일 | `TookTook/Resources/PrivacyPolicy.md`의 `- 이메일:` 줄 | `[문의 이메일을 여기에 적어 주세요]`. 웹에서는 "준비 중"으로 보이고, 지원 페이지 문의란도 이 줄을 따라간다 |

이메일을 채우면 앱 번들과 웹 페이지가 같이 바뀐다. 푸시하면 페이지는 자동으로 다시 게시된다.

## 2. 업로드 전 점검 (서명 없이 가능)
```bash
# 전체 테스트 (현재 117개)
xcodebuild test -project TookTook.xcodeproj -scheme TookTook -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# Release 빌드 (서명 없이)
xcodebuild -project TookTook.xcodeproj -scheme TookTook -configuration Release -destination "generic/platform=iOS" -derivedDataPath build-release CODE_SIGNING_ALLOWED=NO build
```
Release 산출물 `build-release/Build/Products/Release-iphoneos/TookTook.app`에서 확인:
- `plutil -p Info.plist`: 버전 1.0, 빌드 1, `ITSAppUsesNonExemptEncryption = false`, 위치 권한 문구
- `strings TookTook | grep -c TookTookDemo` → 0 (예시 데이터는 DEBUG 전용)
- `Metadata.appintents/extract.actionsdata`에 `CaptureStackIntent`와 autoShortcuts가 있음
- `PrivacyInfo.xcprivacy`, `PrivacyPolicy.md`가 번들에 있음
- 엔타이틀먼트 파일 없음, `Persistence.swift`의 `cloudKitDatabase: .none` 유지 (iCloud 꺼짐)

스크린샷을 다시 찍으면 알파 채널을 없앤다. App Store Connect는 투명도가 있는 이미지를 거부한다.
```bash
xcrun swift tools/flatten-screenshots.swift docs/appstore/screenshots/*.png
sips -g hasAlpha docs/appstore/screenshots/*.png
```

## 3. 서명 설정
1. Xcode에서 TookTook 타깃 › Signing & Capabilities를 연다.
2. "Automatically manage signing"을 켜고 Team을 유료 팀으로 고른다.
   - 지금 `project.pbxproj`의 `DEVELOPMENT_TEAM = 87HJ7X5JK4`는 무료(Personal Team) 시절 값일 수 있다. 0단계의 Team ID와 다르면 바꾼다.
3. Bundle Identifier가 `com.twentyonestar.tooktook`인지 확인한다.
4. Capability는 추가하지 않는다. iCloud, Push, Background Modes 모두 1.0에서는 쓰지 않는다.
5. 바뀐 `project.pbxproj`는 "Set signing team for App Store" 같은 메시지로 커밋한다.

## 4. App Store Connect에 앱 만들기
appstoreconnect.apple.com › 앱 › + › 신규 앱
- 플랫폼 iOS, 이름 `툭툭가계부`, 기본 언어 한국어, 번들 ID `com.twentyonestar.tooktook`, SKU `tooktook-001`, 사용자 액세스 전체
- 나머지 입력값(부제, 설명, 키워드, 카테고리, 연령 등급, App Privacy, 심사 메모)은 `docs/appstore/listing.md`를 그대로 붙여넣는다.
- App Privacy는 "데이터를 수집하지 않음"으로 답한다. 근거는 listing.md에 있다. 역지오코딩을 Apple 지도 서비스가 처리한다는 사실이 처리방침에도 적혀 있다.

이름이 이미 쓰이고 있으면 listing.md의 대안 이름을 쓴다.

## 5. Archive와 업로드
### Xcode로 (권장)
1. 상단 실행 대상을 "Any iOS Device (arm64)"로 바꾼다.
2. Product › Archive를 실행한다.
3. Organizer가 열리면 Distribute App › App Store Connect › Upload를 누른다. 옵션은 기본값을 쓴다.
4. 업로드가 끝나면 App Store Connect › TestFlight에 빌드가 "처리 중"으로 보인다. 10~30분 걸린다.

### 명령줄로 (선택)
`ExportOptions.plist`를 만든다. teamID는 0단계 값이다.
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
```
```bash
xcodebuild archive -project TookTook.xcodeproj -scheme TookTook -configuration Release -destination "generic/platform=iOS" -archivePath build-release/TookTook.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build-release/TookTook.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build-release/export -allowProvisioningUpdates
```
다시 올릴 때는 `CURRENT_PROJECT_VERSION`(빌드 번호)을 2, 3…으로 올린다. 같은 번호는 다시 올릴 수 없다.

## 6. TestFlight 확인
TestFlight › 내부 테스트 그룹에 본인을 추가하고 iPhone의 TestFlight 앱으로 설치한다.

설치 전에 지금 개발 빌드의 실제 기록을 보호한다.
- [ ] 설정 › 기록 내보내기로 JSON 백업을 파일 앱에 저장한다.
- 번들 ID가 같아서 TestFlight 빌드는 기존 앱을 덮어쓰며 데이터는 유지되는 것이 정상이다. 그래도 백업부터 만든다.
- 앱을 지우고 다시 설치하지 않는다. 지우면 기기 안 기록이 사라진다.

확인 항목:
- [ ] 기존 기록·카테고리가 그대로 보인다 (업데이트 설치)
- [ ] 뒷면 탭 두 번 → "지출 기록을 남겼어요", 앱을 열지 않고 저장됨
- [ ] 잠금 화면에서 뒷면 탭으로 기록되는지 (설명문의 "잠금 화면에서도" 문구 근거)
- [ ] 위치 허용 상태에서 "○○구 ○○동"이 표시됨, 위치 끔 상태에서도 기록 저장됨
- [ ] 정리 알림이 정한 시각에 오고, 누르면 기록 탭이 열림
- [ ] 모두 정리하기 → 금액·카테고리 입력 → 내역·통계 반영, 도넛 차트 색이 카테고리마다 다름
- [ ] 설정 › 개인정보 처리방침이 열림
- [ ] 다크 모드, 글자 크기 최대(설정 › 손쉬운 사용 › 더 큰 텍스트)에서 글자가 잘리지 않음
- [ ] VoiceOver로 기록 탭·정리 화면·통계 목록을 읽을 수 있음

## 7. 심사 제출
1. App Store Connect › 앱 › 1.0 준비 중 › 빌드 섹션에서 TestFlight 빌드를 고른다.
2. 스크린샷 4장(6.9인치)을 `01 → 04` 순서로 올린다.
3. 버전 출시는 "수동 출시"를 권장한다. 승인 후 원하는 때 공개할 수 있다.
4. 심사에 추가를 누르고 제출한다. 보통 1~3일 걸린다.
5. 거절되면 사유를 Claude에게 붙여넣는다. 수정은 빌드 번호를 올려 다시 업로드한다.

## 8. 출시 후
- `git tag v1.0.0`을 붙이고 푸시한다.
- `docs/QA_CHECKLIST.md`에 TestFlight 결과를 기록한다.
- iCloud 동기화는 `docs/ICLOUD_MIGRATION_PLAN.md` 순서대로 별도 버전에서 진행한다. 처리방침을 먼저 고친다.
