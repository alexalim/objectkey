# 리눅스에서 App Store까지 (MOKI)

맥 없이 진행합니다. 빌드는 **GitHub Actions의 클라우드 맥(`macos-26`)**, 서명 준비는 리눅스, 테스트는 **본인 아이폰의 TestFlight**로 합니다. ShotSort와 같은 방식이고, 배포 인증서와 App Store Connect API 키는 `~/.shotsort-signing`에 있는 것을 그대로 씁니다.

```
리눅스                  GitHub Actions (macos-26)           Apple
코드 수정 → push  ──▶  build-check: Core 테스트 + 시뮬레이터 빌드
Secrets 등록      ──▶  release-testflight: 서명·업로드  ──▶  App Store Connect → TestFlight → 아이폰
```

## 1. 저장소 올리고 컴파일 확인 (Apple 작업 없이 가능)
푸시하면 **Build check**가 돕니다. iOS 앱 층은 아직 실제 Xcode로 컴파일된 적이 없으므로 **여기서 나오는 오류를 고치는 것이 첫 작업**입니다.
비공개 저장소는 맥 러너 사용량이 월 무료분에서 빨리 차감되니 빌드 횟수를 보면서 씁니다.

## 2. Apple 개발자 사이트 (브라우저)
1. **Identifiers → +** → App IDs → App → 번들 ID `com.aspynlim.moki` (추가 기능 체크 불필요)
2. **Profiles → + → Distribution → App Store Connect** → 위 App ID → 기존 Apple Distribution 인증서 선택 → 이름 `MOKI AppStore` → 다운로드

새 인증서는 필요 없습니다(인증서는 팀 공용).

## 3. App Store Connect (브라우저)
**나의 앱 → + → 신규 앱**: iOS, 이름 `MOKI` (이미 쓰이고 있으면 `MOKI - 물건 단축키`처럼 부제를 붙임), 기본 언어 한국어, 번들 ID `com.aspynlim.moki`, SKU 아무 고유값.
API 키는 ShotSort 때 만든 `AuthKey_H5WA8Q5XC8.p8`을 재사용합니다(팀 키라 모든 앱에 적용).

## 4. GitHub Secrets 등록 (리눅스, 저장소 폴더에서)
```bash
tools/signing.sh secrets ~/Downloads/MOKI_AppStore.mobileprovision ~/.shotsort-signing/AuthKey_H5WA8Q5XC8.p8 <Issuer-ID>
```
프로파일에서 팀 ID·이름을 읽어 보여준 뒤 확인을 받고 8개 Secrets를 등록합니다.

## 5. TestFlight
GitHub → **Actions → Release to TestFlight → Run workflow**. 10~30분 뒤 TestFlight 탭에 빌드가 나타나면 내부 테스트 그룹에 본인을 넣어 설치합니다.
그 다음 README의 **실기기 검증** 항목을 확인합니다.

## 6. 심사 제출 전
- 1024×1024 앱 아이콘 (`ObjectKey/Resources/Assets.xcassets/AppIcon.appiconset`) — 없으면 업로드 검증 실패
- 개인정보처리방침 URL: `docs/privacy.html` 을 공개 위치에 호스팅하고 문의 이메일 기입
- 앱 개인정보: "데이터를 수집하지 않음"
- 스크린샷, README의 App Review Notes
