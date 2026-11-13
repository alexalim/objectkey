import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 버전 문자열 비교 규칙.
final class AppVersionTests: XCTestCase {
    func test_isNewer_comparesNumerically() {
        XCTAssertTrue(AppVersion.isNewer("1.0.4", than: "1.0.3"))
        XCTAssertTrue(AppVersion.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.0.3", than: "1.0.3"))
        XCTAssertFalse(AppVersion.isNewer("1.0.2", than: "1.0.3"))
    }

    func test_isNewer_padsMissingParts() {
        XCTAssertFalse(AppVersion.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(AppVersion.isNewer("1.1.0", than: "1.1"))
        XCTAssertTrue(AppVersion.isNewer("1.1.1", than: "1.1"))
    }

    func test_isNewer_rejectsUnreadable() {
        XCTAssertFalse(AppVersion.isNewer("", than: "1.0.3"))
        XCTAssertFalse(AppVersion.isNewer("1.0.4-beta", than: "1.0.3"))
        XCTAssertFalse(AppVersion.isNewer("1.0.4", than: ""))
    }
}
