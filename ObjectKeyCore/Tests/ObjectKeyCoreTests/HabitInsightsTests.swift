import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 습관 힘 점수, 지난 기간 비교, 건너뛴 날 처리. 시간과 달력은 고정해 결정적으로 본다.
final class HabitInsightsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.firstWeekday = 2
        return c
    }()
    private lazy var start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! // 월요일

    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: start)! }
    private func entries(_ days: [Int]) -> [ProgressEntry] { days.map { ProgressEntry(date: day($0).addingTimeInterval(9 * 3600), amount: 1) } }

    func test_strength_risesSlowly_andOneMissDoesNotDropToZero() {
        let all = HabitStrength.series(entries(Array(0..<30)), goal: nil, schedule: .daily, since: day(0), now: day(29), calendar: calendar)
        let after30 = all.last!.score
        XCTAssertGreaterThan(after30, 0.6)
        XCTAssertLessThan(after30, 0.9, "한 달 만에 만점이 되지 않는다")
        let missed = HabitStrength.series(entries(Array(0..<29)), goal: nil, schedule: .daily, since: day(0), now: day(30), calendar: calendar)
        XCTAssertGreaterThan(missed.last!.score, after30 * 0.9, "하루 놓쳐도 조금만 줄어든다")
    }

    func test_strength_ignoresRestAndSkippedDays_andUnfinishedToday() {
        // 월·수·금 습관. 화·목은 쉬는 날이라 점수가 그대로다.
        let mwf = HabitStrength.series(entries([0, 2]), goal: nil, schedule: .weekdays([2, 4, 6]), since: day(0), now: day(3), calendar: calendar)
        XCTAssertEqual(mwf[1].score, mwf[0].score)
        XCTAssertEqual(mwf[3].score, mwf[2].score)
        // 건너뛴 날도 그대로.
        let skipped = HabitStrength.series(entries([0]), goal: nil, schedule: .daily, skipped: [day(1)], since: day(0), now: day(2), calendar: calendar)
        XCTAssertEqual(skipped[1].score, skipped[0].score)
        // 오늘 아직 안 했으면 깎지 않는다.
        XCTAssertEqual(skipped[2].score, skipped[1].score)
    }

    func test_compare_countsRecentAndPreviousWindows() {
        let result = PeriodCompare.metDays(entries([0, 1, 2, 10, 11, 12, 13]), goal: nil, days: 7, now: day(13), calendar: calendar)
        XCTAssertEqual(result.recent, 4)   // 7~13일
        XCTAssertEqual(result.previous, 3) // 0~6일
    }

    func test_skippedDay_keepsStreak_andLeavesRate() {
        // 월·화 하고 수·목을 건너뛰고 금에 했다. 건너뛴 이틀은 놓친 날이 아니다.
        let e = entries([0, 1, 4])
        let plain = DailyProgress.evaluate(e, goal: nil, now: day(4), calendar: calendar)
        let withSkip = DailyProgress.evaluate(e, goal: nil, skipped: [day(2), day(3)], now: day(4), calendar: calendar)
        XCTAssertEqual(plain.streak, 1)
        XCTAssertEqual(withSkip.streak, 3)
        let rate = DailyProgress.completionRate(e, goal: nil, skipped: [day(2), day(3)], since: day(0), now: day(4), calendar: calendar)
        XCTAssertEqual(rate, 1)
    }

    func test_skippedDays_lowerWeeklyTarget() {
        // 주 3회인데 이틀 건너뛰었으면 그 주는 1번으로 채워진다.
        let p = DailyProgress.evaluate(entries([0]), goal: nil, schedule: .perWeek(3), skipped: [day(1), day(2)], now: day(6), calendar: calendar)
        XCTAssertFalse(p.atRisk)
        let rate = DailyProgress.completionRate(entries([0]), goal: nil, schedule: .perWeek(3), skipped: [day(1), day(2)],
                                                since: day(0), now: day(7), calendar: calendar)
        XCTAssertEqual(rate, 1)
    }
}
