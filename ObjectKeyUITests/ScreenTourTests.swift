import XCTest

// 계층: E2E — 실제 앱을 시뮬레이터에서 띄워(데모 데이터, 메모리 저장소) 주요 화면을 차례로 거치며
// 화면이 열리는지 확인하고 스크린샷을 남긴다. 카메라가 없는 시뮬레이터라 인식 자체는 검증하지 않는다.
final class ScreenTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-demo", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        // 카메라·알림 권한 창이 뜨면 거절한다. 화면 점검에는 권한이 필요 없다.
        addUIInterruptionMonitor(withDescription: "권한") { alert in
            for label in ["Don’t Allow", "Don't Allow", "허용 안 함", "OK", "확인"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
    }

    func test_tour() {
        // 1. 시작 화면 → 누르면 홈
        let start = app.buttons["MOKI 시작하기"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "시작 화면이 보여야 한다")
        snap("01-splash")
        start.tap()
        // 홈은 시작 화면 뒤에 이미 떠 있으므로, 홈이 보이는지가 아니라 시작 화면이 사라졌는지로 확인한다.
        if !start.waitForNonExistence(timeout: 5), start.exists { start.tap() }
        XCTAssertTrue(start.waitForNonExistence(timeout: 5), "누르면 시작 화면이 사라져야 한다")

        // 처음 설치라 소개가 뜬다. 네 장을 넘겨 찍고 시작한다.
        let next = app.buttons["다음"]
        if next.waitForExistence(timeout: 5) {
            snap("01b-onboarding-1")
            for i in 2...4 {
                next.tap()
                if i == 3 { snap("01c-onboarding-3") }
            }
            snap("01d-onboarding-4")
            app.buttons["시작하기"].tap()
        } else {
            XCTFail("처음 설치하면 소개가 보여야 한다")
        }
        snap("02-home")

        // 태그 필터: 운동만 보기 → 전체로 돌아오기
        let tagChip = app.buttons["#운동"]
        if tagChip.waitForExistence(timeout: 3) {
            tagChip.tap()
            snap("02b-home-tag")
            app.buttons["전체"].tap()
        } else {
            XCTFail("태그 필터가 보여야 한다")
        }

        // 2. 행을 누르면 기록하지 않고 실행 화면이 열린다 → 완료 → 완료 피드백
        row("영양제").tap()
        if app.buttons["완료했어요"].waitForExistence(timeout: 5) {
            snap("03-run")
            app.buttons["완료했어요"].tap()
            if app.buttons["오늘 화면으로"].waitForExistence(timeout: 5) {
                snap("03a-done")
                app.buttons["오늘 화면으로"].tap()
            } else {
                XCTFail("완료하면 완료 피드백이 보여야 한다")
            }
        } else {
            XCTFail("행을 누르면 실행 화면이 열려야 한다")
        }

        // 2b. 실행 화면 → 자세히 → 물건 상세
        openDetail("영양제")
        XCTAssertTrue(app.navigationBars["영양제"].waitForExistence(timeout: 5), "상세 화면이 열려야 한다")
        snap("03-detail")
        tapIfExists(app.buttons["통계 보기"])
        if app.navigationBars["영양제 통계"].waitForExistence(timeout: 5) {
            snap("03b-stats")
            app.swipeUp()
            snap("03c-stats-scrolled")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            XCTFail("통계 화면이 열려야 한다")
        }
        app.swipeUp()
        snap("04-detail-scrolled")

        // 3. 달력 날짜 → 고치기 창
        // 데모 기록은 지난 2주다. 달 초에 돌리면 이번 달에 채운 날이 없으니 지난달로 넘긴다.
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "채움")).firstMatch
        if !day.waitForExistence(timeout: 3) { tapIfExists(app.buttons["이전 달"]) }
        if day.waitForExistence(timeout: 3) {
            day.tap()
            snap("05-day-dialog")
            // iOS 26은 확인 창을 말풍선으로 띄우고 취소 버튼 대신 바깥을 누르게 한다.
            if app.buttons["취소"].exists {
                app.buttons["취소"].tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
            }
        } else {
            XCTFail("달력에 채운 날이 있어야 한다")
        }

        // 4. 습관 설정
        // 습관 설정 버튼은 내비게이션 바에 늘 있다. 아래로 쓸면 시트가 닫힐 수 있어 스크롤하지 않는다.
        tapIfExists(app.buttons["습관 설정"])
        if app.navigationBars["영양제 습관 설정"].waitForExistence(timeout: 5) {
            snap("06-goal-editor")
            app.buttons["완료"].tap()
        } else {
            XCTFail("습관 설정이 열려야 한다")
        }
        closeDetail()

        // 5. 요일 지정·주 N회 물건 상세
        openDetail("읽는 책")
        if app.navigationBars["읽는 책"].waitForExistence(timeout: 5) { snap("07-detail-weekdays") }
        closeDetail()
        openDetail("운동 매트")
        if app.navigationBars["운동 매트"].waitForExistence(timeout: 5) { snap("08-detail-perweek") }
        closeDetail()
        openDetail("아이스하키")
        if app.navigationBars["아이스하키 수업"].waitForExistence(timeout: 5) {
            snap("08b-detail-attend")
            tapIfExists(app.buttons["습관 설정"])
            if app.navigationBars["아이스하키 수업 습관 설정"].waitForExistence(timeout: 5) {
                snap("08c-attend-settings")
                app.buttons["완료"].tap()
            }
        } else {
            XCTFail("참석 물건 상세가 열려야 한다")
        }
        closeDetail()

        // 6. 행 밀기 → 습관 버튼
        row("영양제").swipeRight()
        snap("09-swipe")
        // 화면 가운데를 누르면 요일에 따라 다른 행이 눌려 상세가 열릴 수 있다. 제목을 눌러 되돌리고, 혹시 열린 창은 닫는다.
        app.navigationBars["오늘"].tap()
        closeTop()

        // 7. 가운데 + → 새로 만들기 시트 → 이름만 적어 등록
        app.tabBars.buttons["새로 만들기"].tap()
        if app.navigationBars["어떻게 시작할까요?"].waitForExistence(timeout: 5) {
            snap("10a-quick-add")
        } else {
            XCTFail("가운데 +를 누르면 새로 만들기 시트가 열려야 한다")
        }
        // 버튼 이름에 설명까지 붙어 읽히므로 앞부분으로 찾는다.
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "이름만 적어 등록")).firstMatch)
        if app.navigationBars["새 물건 등록"].waitForExistence(timeout: 5) {
            snap("10-register")
            app.swipeUp()
            snap("11-register-scrolled")
            app.buttons["취소"].tap()
        } else {
            XCTFail("등록 화면이 열려야 한다")
        }
        closeTop()

        // 7a. 습관 탭
        app.tabBars.buttons["습관"].tap()
        if app.navigationBars["습관"].waitForExistence(timeout: 5) { snap("13-objects") } else { XCTFail("습관 탭이 열려야 한다") }
        // 운동 매트에는 습관이 둘(운동 매트, 아침 스트레칭) 걸려 있다.
        row("운동 매트").tap()
        if app.navigationBars["물건"].waitForExistence(timeout: 5) {
            snap("13b-object")
            XCTAssertTrue(app.staticTexts["아침 스트레칭"].exists, "같은 물건의 습관이 함께 보여야 한다")
            closeTop()
        } else {
            XCTFail("물건을 누르면 물건 상세가 열려야 한다")
        }
        app.tabBars.buttons["통계"].tap()
        if app.navigationBars["통계"].waitForExistence(timeout: 5) { snap("14-stats") } else { XCTFail("통계 탭이 열려야 한다") }
        // 이번 주 돌아보기·습관 목록 아래에 있어 화면 밖일 수 있다. 넘겨 가며 찾는다.
        row("전체 기록 보기").tap()
        if app.navigationBars["기록"].waitForExistence(timeout: 5) {
            snap("14b-history")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            XCTFail("통계에서 전체 기록으로 들어갈 수 있어야 한다")
        }

        // 7b. 마이 → 사용 안내
        app.tabBars.buttons["마이"].tap()
        if app.navigationBars["마이"].waitForExistence(timeout: 5) { snap("15-my") } else { XCTFail("마이 탭이 열려야 한다") }
        tapIfExists(app.buttons["사용 안내"])
        if app.navigationBars["사용 안내"].waitForExistence(timeout: 5) {
            snap("10c-help")
            app.swipeUp()
            snap("10d-help-scrolled")
            app.buttons["완료"].tap()
        } else {
            XCTFail("사용 안내가 열려야 한다")
        }

        // 8. 스캔 화면 (시뮬레이터에는 카메라가 없다)
        app.tabBars.buttons["오늘"].tap()
        tapIfExists(app.buttons["물건 스캔"])
        sleep(2)
        app.tap()
        snap("12-scan")
    }

    /// 무료 상태의 결제 화면. App Store 인앱 구입 심사용 스크린샷으로도 쓴다.
    func test_paywall() {
        app.terminate()
        app.launchArguments += ["-ui-free"]
        app.launch()
        let start = app.buttons["MOKI 시작하기"]
        if start.waitForExistence(timeout: 10) { start.tap() }
        if app.buttons["건너뛰기"].waitForExistence(timeout: 3) { app.buttons["건너뛰기"].tap() }
        app.tabBars.buttons["마이"].tap()
        let plus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "MOKI 플러스")).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "마이에 플러스 줄이 보여야 한다")
        plus.tap()
        XCTAssertTrue(app.staticTexts["습관 개수 제한 없음"].waitForExistence(timeout: 5), "결제 화면이 열려야 한다")
        sleep(2)
        snap("20-paywall")
    }

    /// 목록이 길면 화면 밖 행은 아직 만들어지지 않는다. 위아래로 넘겨 가며 찾는다.
    private func row(_ name: String) -> XCUIElement {
        let element = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        if element.waitForExistence(timeout: 1) && element.isHittable { return element }
        for _ in 0..<4 where !(element.exists && element.isHittable) { app.swipeUp() }
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeDown() }
        return element
    }

    /// 행 → 실행 화면 → 자세히. 상세는 실행 화면 위에 뜬다.
    private func openDetail(_ name: String) {
        row(name).tap()
        tapIfExists(app.buttons["자세히"])
    }

    /// 상세와 그 아래 실행 화면을 차례로 닫는다.
    private func closeDetail() {
        closeTop()
        closeTop()
    }

    /// 시트가 겹치면 "닫기"가 여러 개 잡힌다. 맨 위(누를 수 있는) 것만 누른다.
    private func closeTop() {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "닫기"))
        _ = buttons.firstMatch.waitForExistence(timeout: 2)
        for button in buttons.allElementsBoundByIndex.reversed() where button.isHittable {
            button.tap()
            return
        }
    }

    private func tapIfExists(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 2) { element.tap() }
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
