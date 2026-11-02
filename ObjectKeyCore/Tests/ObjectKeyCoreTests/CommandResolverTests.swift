import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 자연어 해석 결과를 앱 값으로 옮기는 규칙. 언어 모델 없이 결정적으로 검증한다.
final class CommandResolverTests: XCTestCase {
    func test_minuteOfDay_readsCommonKoreanForms() {
        XCTAssertEqual(CommandResolver.minuteOfDay("21:00"), 1260)
        XCTAssertEqual(CommandResolver.minuteOfDay("9:30"), 570)
        XCTAssertEqual(CommandResolver.minuteOfDay("21시"), 1260)
        XCTAssertEqual(CommandResolver.minuteOfDay("밤 9시 30분"), 1290)
        XCTAssertEqual(CommandResolver.minuteOfDay("오전 12시"), 0)
        XCTAssertEqual(CommandResolver.minuteOfDay("9시 반"), 570)
        XCTAssertEqual(CommandResolver.minuteOfDay("저녁 9시 반"), 1290)
        XCTAssertEqual(CommandResolver.minuteOfDay("밤 12시"), 0)
        XCTAssertEqual(CommandResolver.minuteOfDay("밤 9시"), 1260)
        XCTAssertNil(CommandResolver.minuteOfDay("25:00"))
        XCTAssertNil(CommandResolver.minuteOfDay(nil))
        XCTAssertNil(CommandResolver.minuteOfDay("저녁"))
    }

    func test_weekdays_fromNames_notNumbers() {
        XCTAssertEqual(CommandResolver.weekdays(["화요일"]), [3])
        XCTAssertEqual(CommandResolver.weekdays(["월", "수", "금"]), [2, 4, 6])
        XCTAssertEqual(CommandResolver.weekdays(["평일"]), [2, 3, 4, 5, 6])
        XCTAssertEqual(CommandResolver.weekdays(["주말", "Tue"]), [1, 3, 7])
        XCTAssertEqual(CommandResolver.weekdays(["매일"]), [])
        XCTAssertEqual(CommandResolver.weekdays(nil), [])
    }

    func test_recordDaysAgo_isClampedToPastMonth() {
        XCTAssertEqual(CommandResolver.recordDaysAgo(nil), 0)
        XCTAssertEqual(CommandResolver.recordDaysAgo(1), 1)
        XCTAssertEqual(CommandResolver.recordDaysAgo(-2), 0, "미래는 오늘로")
        XCTAssertEqual(CommandResolver.recordDaysAgo(400), 30)
    }

    func test_schedule_prefersWeekdaysThenTimesPerWeek() {
        XCTAssertEqual(CommandResolver.schedule(weekdays: [3], timesPerWeek: nil), .weekdays([3]))
        XCTAssertEqual(CommandResolver.schedule(weekdays: [0, 9], timesPerWeek: 3), .perWeek(3), "범위 밖 요일은 버린다")
        XCTAssertEqual(CommandResolver.schedule(weekdays: Array(1...7), timesPerWeek: nil), .daily)
        XCTAssertEqual(CommandResolver.schedule(weekdays: nil, timesPerWeek: 7), .daily)
    }

    func test_reminderMinute_explicitThenBeforeStart() {
        XCTAssertEqual(CommandResolver.reminderMinute(start: 1260, reminder: 1200, before: 30), 1200)
        XCTAssertEqual(CommandResolver.reminderMinute(start: 1260, reminder: nil, before: 30), 1230)
        XCTAssertEqual(CommandResolver.reminderMinute(start: 10, reminder: nil, before: 30), 1420, "자정을 넘기면 전날 시각")
        XCTAssertEqual(CommandResolver.reminderMinute(start: nil, reminder: nil, before: 30), -1)
    }

    func test_matchKey_toleratesSpacingAndParticles() {
        let book = UUID(), pill = UUID(), hockey = UUID()
        let keys = [(id: book, name: "읽는 책"), (id: pill, name: "사무실 영양제"), (id: hockey, name: "아이스하키 수업")]
        XCTAssertEqual(CommandResolver.matchKey("영양제", among: keys), pill)
        XCTAssertEqual(CommandResolver.matchKey("아이스 하키", among: keys), hockey)
        XCTAssertEqual(CommandResolver.matchKey("읽는책", among: keys), book)
        XCTAssertNil(CommandResolver.matchKey("자전거", among: keys))
    }
}
