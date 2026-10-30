import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 알림 예약 시각 계산. Calendar를 UTC로 고정해 결정적으로 검증한다.
final class ReminderPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-29 15:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_286_000)

    private func plan(_ minute: Int, met: Bool = false, days: Int = 3) -> [Date] {
        ReminderPlan.fireDates(minuteOfDay: minute, metToday: met, days: days, now: now, calendar: calendar)
    }
    private func hoursFromNow(_ dates: [Date]) -> [Double] { dates.map { $0.timeIntervalSince(now) / 3600 } }

    func test_laterToday_includesToday() {
        XCTAssertEqual(hoursFromNow(plan(21 * 60)), [6, 30, 54])
    }

    func test_alreadyMetToday_skipsToday() {
        XCTAssertEqual(hoursFromNow(plan(21 * 60, met: true)), [30, 54])
    }

    func test_timeAlreadyPassed_startsTomorrow() {
        XCTAssertEqual(hoursFromNow(plan(9 * 60)), [18, 42])
    }

    func test_invalidInput_isEmpty() {
        XCTAssertEqual(plan(-1), [])
        XCTAssertEqual(plan(24 * 60), [])
        XCTAssertEqual(plan(9 * 60, days: 0), [])
    }
}
