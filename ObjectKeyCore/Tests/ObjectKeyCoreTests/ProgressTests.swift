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

    // MARK: 이틀 규칙 — 하루 빠지면 이어지고, 이틀 연속 빠지면 끊긴다

    func test_singleMissedDay_keepsChain_andCountsOnlyMetDays() {
        // 4·3 채움, 2 빠짐, 1·0 채움 → 끊기지 않고 채운 날 4일.
        let p = eval([entry(4, 1), entry(3, 1), entry(1, 1), entry(0, 1)])
        XCTAssertEqual(p.streak, 4)
        XCTAssertFalse(p.atRisk)
    }

    func test_twoMissedDaysInARow_breakChain() {
        // 4 채움, 3·2 빠짐, 1·0 채움 → 이틀 연속 빠진 곳에서 끊겨 2일.
        XCTAssertEqual(eval([entry(4, 1), entry(1, 1), entry(0, 1)]).streak, 2)
    }

    func test_yesterdayMissed_todayNotYet_isAliveButAtRisk() {
        let p = eval([entry(3, 1), entry(2, 1)])
        XCTAssertEqual(p.streak, 2)
        XCTAssertTrue(p.atRisk)
        // 오늘 채우면 위험이 사라지고 이어진다.
        let filled = eval([entry(3, 1), entry(2, 1), entry(0, 1)])
        XCTAssertEqual(filled.streak, 3)
        XCTAssertFalse(filled.atRisk)
    }

    func test_twoMissedDaysBeforeToday_isZero() {
        let p = eval([entry(3, 1)])
        XCTAssertEqual(p.streak, 0)
        XCTAssertFalse(p.atRisk)
    }

    func test_todayOnly_isNotAtRisk() {
        XCTAssertFalse(eval([entry(0, 1)]).atRisk)
    }

    // MARK: 66일 단계

    func test_phaseBoundaries() {
        XCTAssertNil(HabitPhase(day: 0))
        XCTAssertEqual(HabitPhase(day: 1), .adapting)
        XCTAssertEqual(HabitPhase(day: 22), .adapting)
        XCTAssertEqual(HabitPhase(day: 23), .wiring)
        XCTAssertEqual(HabitPhase(day: 44), .wiring)
        XCTAssertEqual(HabitPhase(day: 45), .automating)
        XCTAssertEqual(HabitPhase(day: 66), .automating)
        XCTAssertEqual(HabitPhase(day: 67), .formed)
    }

    func test_phaseFollowsChain_notFirstRecord() {
        // 30일 전에 한 번 기록했지만 이틀 넘게 끊겼다가 최근 3일만 채움 → 1단계.
        let p = eval([entry(30, 1), entry(2, 1), entry(1, 1), entry(0, 1)])
        XCTAssertEqual(p.streak, 3)
        XCTAssertEqual(p.phase, .adapting)
    }

    func test_goal_onlyDaysMeetingGoalCount() {
        let goal: Double = 1800
        // 2일 전만 목표 달성, 어제는 기록은 있지만 미달 → 빠진 날. 오늘도 아직 미달이라 위험.
        let p = eval([entry(2, 1800), entry(1, 1200), entry(0, 600)], goal: goal)
        XCTAssertEqual(p.streak, 1)
        XCTAssertTrue(p.atRisk)
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
