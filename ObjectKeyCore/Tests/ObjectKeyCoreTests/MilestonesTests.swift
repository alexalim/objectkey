import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 스티커 기준과 알림 줄이기 규칙.
final class MilestonesTests: XCTestCase {
    func test_unlocked_countsThresholdsReached() {
        XCTAssertEqual(Milestones.unlocked(bestStreak: 0), 0)
        XCTAssertEqual(Milestones.unlocked(bestStreak: 1), 1)
        XCTAssertEqual(Milestones.unlocked(bestStreak: 7), 3)
        XCTAssertEqual(Milestones.unlocked(bestStreak: 66), 8)
        XCTAssertEqual(Milestones.unlocked(bestStreak: 1000), Milestones.streakDays.count)
    }

    func test_daysToNext() {
        XCTAssertEqual(Milestones.daysToNext(bestStreak: 5), 2)
        XCTAssertNil(Milestones.daysToNext(bestStreak: 365))
    }

    func test_thin_reducesRemindersWhenIdle() {
        let dates = (0..<6).map { Date(timeIntervalSince1970: TimeInterval($0) * 86_400) }
        XCTAssertEqual(ReminderPlan.thin(dates, idleDays: 3), dates)
        XCTAssertEqual(ReminderPlan.thin(dates, idleDays: 8), [dates[0], dates[2], dates[4]])
        XCTAssertEqual(ReminderPlan.thin(dates, idleDays: 20), [dates[0]])
        XCTAssertEqual(ReminderPlan.thin([], idleDays: 20), [])
    }
}
