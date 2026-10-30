# MOKI (모키)

> 내부 코드명: ObjectKey (타깃·폴더·`ObjectKeyCore` 패키지 이름)

평범한 물건이 나만의 버튼이 되는 iPhone 앱입니다. 책을 비추면 독서 시간 기록이 시작되고, 컵을 비추면 휴식 타이머가 돌아갑니다.

## v0.1 범위 (MVP 필수 항목만)

| 기능 | 구현 위치 |
|---|---|
| 물건 등록·이름·이모지·동작 지정 | `ObjectKey/Views/RegisterView.swift` |
| 물건별 참조 사진 3~6장 | 같은 파일, `ReferenceShot` 모델 |
| 카메라 특징값 비교 | `FeaturePrinter` (Vision 물체 saliency로 가이드 안 물체 상자를 찾아 그 영역만 feature print) + `ObjectMatcher` |
| 인식 후보 확인·수동 선택 | `ScanView` 선택 창, "직접 선택", 홈 목록 탭 |
| 시간 기록·휴식 타이머·횟수 카운터 | `ActivityEngine` + `ActivityStore` |
| 로컬 저장·삭제 | SwiftData, `HistoryView`의 모든 데이터 삭제 |

## v0.2 챌린지 (서버 없음)

| 기능 | 구현 위치 |
|---|---|
| 연속 일수(스트릭)·하루 목표 계산 | `ObjectKeyCore/DailyProgress.swift` (Unit 테스트 `ProgressTests`) |
| 하루 목표 입력·수정 | `GoalStepper`(등록 화면), `GoalEditor`(홈 목록 길게 누르기) |
| 행별 진행률 링·불꽃 | `ProgressMark` |
| 오늘 상태에 반응하는 MOKI | `MoodHeader` (홈 상단) |

규칙: 목표가 있으면 그날 목표를 채운 날, 없으면 하루 한 번이라도 기록된 날을 "채운 날"로 본다. 오늘은 하루가 끝나기 전이라 빠진 날로 치지 않는다. 휴식 타이머는 기록이 남지 않으므로 대상이 아니다. 진행 중인 세션의 경과 시간도 오늘 진행에 포함된다.

## v0.3 습관 형성 (66일 법칙)

| 원칙 | 반영 |
|---|---|
| 이틀 규칙 | 하루 빠져도 이어지고 이틀 연속 빠지면 끊긴다. 일수는 채운 날만 센다. 어제 빠지고 오늘 아직이면 `atRisk` → 빨간 불꽃 + 홈 상단 경고 |
| 66일 3단계 | 이어온 일수로 `HabitPhase` 결정 (1~22 적응 / 23~44 회로 형성 / 45~66 자동화 / 66+ 안착). 첫 기록일이 아니라 현재 이어지는 사슬 기준 |
| 습관 쪼개기 | 목표 없음(하루 1번 비추기)을 기본으로 권하는 안내 문구 |
| 습관 쌓기 | `KeyObject.cue` — "커피 내린 다음에"처럼 목록 행에 표시 |

v0.4: 습관 알림(`KeyObject.reminderMinute`). 매일 반복 알림은 "이미 했으면 건너뛰기"가 안 되므로 `ReminderPlan`으로 며칠 치를 한 번짜리로 예약하고 앱을 열거나 기록할 때 다시 계산한다. 습관 설정은 목록 행을 오른쪽으로 밀어서도 연다. 일정(`HabitSchedule`)은 매일·요일 지정·주 N회 — 요일 지정은 정한 요일만 기회로 보고(다른 날 한 것도 셈), 주 N회는 한 주가 한 번의 기회다. 이틀 규칙은 "기회를 두 번 연속 놓치면 끊김"으로 일반화했다. 목록 행을 누르면 바로 기록하지 않고 상세 화면(`KeyDetailView`)이 열린다 — 현재·최고 기록, 달력, 지금 기록 버튼, 달력 날짜를 눌러 깜빡한 날 기록 추가·삭제.

2차 이후로 미룬 것: 동작 버튼·위젯(App Intents), 루틴 템플릿 공유, 물건 조합, 인앱 결제(Pro), 클라우드 동기화.

## 구조

```
ObjectKeyCore/   Foundation만 쓰는 판단 로직 (Linux에서도 테스트 가능)
  Matching.swift        거리 비교 · 임계값 · 1/2위 비율 모호 판정 · 연속 프레임 안정화 · 임계값 제안
  ActivityEngine.swift  인식 결과 → 동작 상태 전이 (세션 토글, 휴식 중 세션 일시정지, 전환 확인)
ObjectKey/       iOS 앱 (SwiftUI · SwiftData · AVFoundation · Vision)
project.yml      XcodeGen 정의
```

**안전 원칙:** 인식 결과가 `match`일 때만 동작이 실행됩니다. `ambiguous`면 사용자가 고르게 하고, `noMatch`면 아무것도 하지 않습니다. 같은 결과가 연속 3프레임 이어져야 확정합니다.

## 테스트

```bash
# Linux (Docker)
docker run --rm -v "$PWD/ObjectKeyCore":/pkg -w /pkg swift:6.1-jammy swift test --scratch-path /tmp/build
# macOS
swift test --package-path ObjectKeyCore
```

계층은 전부 Unit입니다. iOS 앱 층(카메라·Vision 실측)은 실기기에서 수동으로 검증합니다.

## 빌드와 배포 (리눅스 + GitHub Actions)

맥 없이 진행합니다. 자세한 순서는 [`docs/RELEASE_FROM_LINUX.md`](docs/RELEASE_FROM_LINUX.md)에 있습니다.

- 푸시할 때마다 `build-check`가 돌면서 Core 테스트와 시뮬레이터 빌드(서명 없음)를 실행합니다.
- `Release to TestFlight` 워크플로우를 수동으로 실행하면 서명한 뒤 App Store Connect에 업로드합니다.

## 실기기 검증 (가장 먼저 할 것)

오실행 위험이 가장 큰 경우부터 확인합니다. 기획서의 "등록 물건과 미등록 물건을 모두 포함한 정확도"가 바로 이 경우입니다.

1. **물건을 하나만 등록한 상태에서 물건 없이 같은 책상만 비춘다 → 실행되면 안 된다.** 등록 물건이 1개면 1·2위 비교를 할 수 없어서, 절대 임계값 하나로만 판정합니다.
2. **배경 학습 확인:** 등록한 물건을 다른 장소(다른 책상·바닥)에서 비춰도 인식되는지, 등록 장소의 빈 배경에는 반응하지 않는지 확인합니다.
3. 비슷한 물건 구별: 흰 컵 두 개, 표지가 비슷한 책 두 권
4. 조명·각도를 바꿔 인식 정확도 95%, 카메라를 연 뒤 3초 안팎 인식

## 실기기에서 조정할 값 (기기 실측 전 가설값)

- `Calibration.minimumThreshold` 0.45 / `maximumThreshold` 0.72 / `marginFactor` 1.2 — 2026-10-29 실측 기준(같은 물건 ≥0.56, 다른 물건 0.78, 무관 1.01). 실측 전 가설값은 0.35 / 0.9 / 1.6이었고 오실행을 냈다.
- `MatcherConfig.ambiguityRatio` 0.85
- `StabilityFilter.requiredStreak` 3, 프레임 간격 0.2초

기획서 검증 지표: 인식 정확도 95%(등록·미등록 물건 모두 포함), 카메라를 연 뒤 3초 안팎에 인식, 미확인 오실행 0건, 7일 동안 3일 이상 재사용.

## App Review Notes 초안

> MOKI does not require an account or a server. To try it: tap "+", name any object (e.g. a mug), take 3 photos of it, and save. Then tap "물건 비추기" and point the camera at the same object, or tap the object in the list to run its action without the camera. All data stays on the device.
