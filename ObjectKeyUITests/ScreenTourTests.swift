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
        XCTAssertTrue(app.navigationBars["MOKI"].waitForExistence(timeout: 5), "홈으로 넘어가야 한다")
        snap("02-home")

        // 2. 물건 상세: 행을 누르면 기록하지 않고 상세가 열린다
        row("영양제").tap()
        XCTAssertTrue(app.navigationBars["영양제"].waitForExistence(timeout: 5), "상세 화면이 열려야 한다")
        snap("03-detail")
        app.swipeUp()
        snap("04-detail-scrolled")

        // 3. 달력 날짜 → 고치기 창
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "채움")).firstMatch
        if day.waitForExistence(timeout: 3) {
            day.tap()
            snap("05-day-dialog")
            tapIfExists(app.buttons["취소"])
        } else {
            XCTFail("달력에 채운 날이 있어야 한다")
        }

        // 4. 습관 설정
        app.swipeDown()
        tapIfExists(app.buttons["습관 설정"])
        if app.navigationBars["영양제 습관 설정"].waitForExistence(timeout: 5) {
            snap("06-goal-editor")
            app.buttons["완료"].tap()
        } else {
            XCTFail("습관 설정이 열려야 한다")
        }
        tapIfExists(app.buttons["닫기"])

        // 5. 요일 지정·주 N회 물건 상세
        row("읽는 책").tap()
        if app.navigationBars["읽는 책"].waitForExistence(timeout: 5) { snap("07-detail-weekdays") }
        tapIfExists(app.buttons["닫기"])
        row("운동 매트").tap()
        if app.navigationBars["운동 매트"].waitForExistence(timeout: 5) { snap("08-detail-perweek") }
        tapIfExists(app.buttons["닫기"])

        // 6. 행 밀기 → 습관 버튼
        row("영양제").swipeRight()
        snap("09-swipe")
        app.tap() // 밀린 행 되돌리기

        // 7. 등록 화면
        app.buttons["물건 등록"].tap()
        app.tap() // 권한 창 처리를 위해 앱과 상호작용
        if app.navigationBars["새 물건 등록"].waitForExistence(timeout: 5) {
            snap("10-register")
            app.swipeUp()
            snap("11-register-scrolled")
            app.buttons["취소"].tap()
        } else {
            XCTFail("등록 화면이 열려야 한다")
        }

        // 8. 스캔 화면 (시뮬레이터에는 카메라가 없다)
        tapIfExists(app.buttons["물건 비추기"])
        sleep(2)
        app.tap()
        snap("12-scan")
    }

    private func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
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
