import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 날짜 합산·연속 일수 계산. Calendar를 UTC로 고정해 결정적으로 검증한다.
final class ProgressTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-29 15:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_286_000)

    private func daysAgo(_ n: Int, hour: Int = 10) -> Date {
        let day = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))!
        return day.addingTimeInterval(TimeInterval(hour * 3600))
    }
    private func entry(_ daysAgo: Int, _ amount: Double, hour: Int = 10) -> ProgressEntry {
        ProgressEntry(date: self.daysAgo(daysAgo, hour: hour), amount: amount)
    }
    private func eval(_ entries: [ProgressEntry], goal: Double? = nil) -> KeyProgress {
        DailyProgress.evaluate(entries, goal: goal, now: now, calendar: calendar)
    }

    func test_noEntries_isZero() {
        let p = eval([])
        XCTAssertEqual(p, KeyProgress(today: 0, goal: nil, streak: 0))
        XCTAssertFalse(p.metToday)
        XCTAssertNil(p.fraction)
    }

    func test_todayOnly_withoutGoal_countsAsStreakOfOne() {
        let p = eval([entry(0, 600)])
        XCTAssertEqual(p.streak, 1)
        XCTAssertTrue(p.metToday)
    }

    func test_consecutiveDaysEndingYesterday_keepStreakAlive_untilTodayIsFilled() {
        let p = eval([entry(3, 1), entry(2, 1), entry(1, 1)])
        XCTAssertEqual(p.streak, 3)
        XCTAssertFalse(p.metToday)
        XCTAssertEqual(eval([entry(3, 1), entry(2, 1), entry(1, 1), entry(0, 1)]).streak, 4)
    }

    func test_gapBreaksStreak() {
        XCTAssertEqual(eval([entry(4, 1), entry(3, 1), entry(1, 1), entry(0, 1)]).streak, 2)
        XCTAssertEqual(eval([entry(2, 1)]).streak, 0)
    }

    func test_goal_onlyDaysMeetingGoalCount() {
        let goal: Double = 1800
        let p = eval([entry(2, 1800), entry(1, 1200), entry(0, 600)], goal: goal)
        XCTAssertEqual(p.streak, 0)
        XCTAssertEqual(p.today, 600)
        XCTAssertEqual(p.fraction!, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(p.metToday)
    }

    func test_sameDayEntriesAreSummed_andFractionCapsAtOne() {
        let p = eval([entry(0, 1200, hour: 9), entry(0, 1200, hour: 20)], goal: 1800)
        XCTAssertEqual(p.today, 2400)
        XCTAssertEqual(p.fraction, 1)
        XCTAssertTrue(p.metToday)
        XCTAssertEqual(p.streak, 1)
    }

    func test_midnightBoundary_followsCalendar() {
        // 어제 23:59과 오늘 00:01은 다른 날.
        let p = eval([entry(1, 1, hour: 23), entry(0, 1, hour: 0)])
        XCTAssertEqual(p.streak, 2)
    }

    func test_zeroGoal_meansNoGoal() {
        let p = eval([entry(0, 1)], goal: 0)
        XCTAssertNil(p.goal)
        XCTAssertNil(p.fraction)
        XCTAssertTrue(p.metToday)
    }
}
