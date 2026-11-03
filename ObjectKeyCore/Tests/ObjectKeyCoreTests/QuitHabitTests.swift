import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 끊기 습관: 실수 기록에서 지킨 날을 만들어 기존 계산(연속·이틀 규칙·완료율)을 그대로 쓰는지.
final class QuitHabitTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-29 15:00 UTC (목)
    private let now = Date(timeIntervalSince1970: 1_793_286_000)

    private func daysAgo(_ n: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))!.addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func progress(slips: [Int], startedDaysAgo: Int) -> KeyProgress {
        let entries = QuitHabit.cleanDays(slips: slips.map { daysAgo($0) }, since: daysAgo(startedDaysAgo, hour: 0), now: now, calendar: calendar)
        return DailyProgress.evaluate(entries, goal: nil, now: now, calendar: calendar)
    }

    func test_noSlips_everyDaySinceStartCounts_includingToday() {
        let p = progress(slips: [], startedDaysAgo: 4)
        XCTAssertEqual(p.streak, 5)
        XCTAssertTrue(p.metToday, "실수가 없으면 오늘도 지킨 것으로 보인다")
        XCTAssertFalse(p.atRisk)
    }

    func test_brandNewQuitHabit_startsAtOneNotZero() {
        XCTAssertEqual(progress(slips: [], startedDaysAgo: 0).streak, 1, "기록이 하나도 없어도 0일이 아니다")
    }

    func test_oneSlipDay_keepsChain_twoInARowBreaks() {
        XCTAssertEqual(progress(slips: [2], startedDaysAgo: 5).streak, 5, "하루 실수는 이어진다(그날은 세지 않음)")
        XCTAssertEqual(progress(slips: [3, 2], startedDaysAgo: 6).streak, 2, "이틀 연속 실수에서 끊긴다")
    }

    func test_slipToday_isNotMet_andAtRiskAfterYesterdaySlip() {
        let today = progress(slips: [0], startedDaysAgo: 3)
        XCTAssertFalse(today.metToday)
        let risky = progress(slips: [1], startedDaysAgo: 5)
        XCTAssertTrue(risky.metToday, "오늘은 아직 실수가 없다")
        XCTAssertFalse(risky.atRisk, "오늘 지키고 있으면 위험이 아니다")
    }

    func test_completionRate_countsCleanDays() {
        let entries = QuitHabit.cleanDays(slips: [daysAgo(1)], since: daysAgo(3, hour: 0), now: now, calendar: calendar)
        let rate = DailyProgress.completionRate(entries, goal: nil, since: daysAgo(3, hour: 0), now: now, calendar: calendar)
        XCTAssertEqual(rate!, 0.75, accuracy: 1e-9, "4일 중 3일 지킴(오늘 포함)")
    }
}
