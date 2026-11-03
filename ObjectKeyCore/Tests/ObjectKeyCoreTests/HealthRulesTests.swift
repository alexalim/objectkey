import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 건강 앱 값으로 자동 기록할 날 고르기. 목표 미달·이미 기록한 날은 빼고, 하루 한 번만.
final class HealthRulesTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let today = Date(timeIntervalSince1970: 1_793_232_000) // 2026-10-29 00:00 UTC

    private func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: today)! }

    func test_onlyDaysOverTarget_andNotYetRecorded() {
        let values = [day(0): 7200, day(1): 3000, day(2): 6000, day(3): 9000.0]
        let days = HealthRules.daysToRecord(values: values, target: 6000, alreadyRecorded: [day(3).addingTimeInterval(3600)], calendar: calendar)
        XCTAssertEqual(days, [day(2), day(0)], "목표 이상(같음 포함)이고 아직 기록 없는 날만, 오래된 순")
    }

    func test_runningTwice_addsNothingNew() {
        let values = [day(0): 7200.0]
        let first = HealthRules.daysToRecord(values: values, target: 6000, alreadyRecorded: [], calendar: calendar)
        let second = HealthRules.daysToRecord(values: values, target: 6000, alreadyRecorded: Set(first), calendar: calendar)
        XCTAssertEqual(first, [day(0)])
        XCTAssertEqual(second, [])
    }

    func test_zeroTarget_recordsNothing() {
        XCTAssertEqual(HealthRules.daysToRecord(values: [day(0): 100], target: 0, alreadyRecorded: [], calendar: calendar), [])
    }
}
