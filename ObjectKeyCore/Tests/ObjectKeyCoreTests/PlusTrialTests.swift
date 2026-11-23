import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 플러스 맛보기 기간 계산(7일 경계 포함).
final class PlusTrialTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    func test_ownedWinsOverTrial() {
        XCTAssertEqual(PlusTrial.access(owned: true, trialStarted: start, now: start), .owned)
        XCTAssertEqual(PlusTrial.access(owned: true, trialStarted: nil, now: start), .owned)
    }

    func test_noTrial() {
        XCTAssertEqual(PlusTrial.access(owned: false, trialStarted: nil, now: start), .none)
        XCTAssertFalse(PlusAccess.none.grantsPlus)
    }

    func test_sevenDayBoundary() {
        let end = start.addingTimeInterval(7 * day)
        XCTAssertEqual(PlusTrial.access(owned: false, trialStarted: start, now: end.addingTimeInterval(-1)), .trial(endsAt: end))
        XCTAssertEqual(PlusTrial.access(owned: false, trialStarted: start, now: end), .trialUsed)
        XCTAssertTrue(PlusAccess.trial(endsAt: end).grantsPlus)
        XCTAssertFalse(PlusAccess.trialUsed.grantsPlus)
    }

    func test_daysLeft_roundsUp() {
        let end = start.addingTimeInterval(7 * day)
        XCTAssertEqual(PlusTrial.daysLeft(until: end, now: start), 7)
        XCTAssertEqual(PlusTrial.daysLeft(until: end, now: end.addingTimeInterval(-3600)), 1)
        XCTAssertEqual(PlusTrial.daysLeft(until: end, now: end.addingTimeInterval(10)), 0)
    }
}
