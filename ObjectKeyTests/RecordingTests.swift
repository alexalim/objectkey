import SwiftData
import XCTest
import ObjectKeyCore
@testable import MOKI

// 계층: Integration — 실제 SwiftData 저장소(메모리)에 ActivityStore.addRecord로 기록한다.
// 상세 화면 "기록 추가"와 모키에게 말하기가 같이 쓰는 규칙(참석 하루 한 번, 수치 습관 양, 지난 날 정오)을 확인한다.
@MainActor
final class RecordingTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar.current

    override func setUp() async throws {
        context = ModelContext(try AppTestStore.make())
    }

    private func logs(_ key: KeyObject) throws -> [ActivityLog] {
        try context.fetch(FetchDescriptor<ActivityLog>()).filter { $0.keyID == key.id }
    }

    func testAttendIsRecordedOncePerDay() throws {
        let hockey = KeyObject(name: "아이스하키", emoji: "🏒", action: .attend(startMinute: 21 * 60, minutes: 90), threshold: 0.6)
        context.insert(hockey)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!

        XCTAssertNil(ActivityStore.shared.addRecord(hockey, on: yesterday, minutes: 90, context: context))
        XCTAssertNotNil(ActivityStore.shared.addRecord(hockey, on: yesterday, minutes: 90, context: context))
        XCTAssertEqual(try logs(hockey).count, 1)
        XCTAssertEqual(try logs(hockey).first?.duration, 90 * 60)
    }

    func testMeasuredHabitRecordsItsStepPerCount() throws {
        let water = KeyObject(name: "물", emoji: "💧", action: .counter, threshold: 0.6)
        water.measureStep = 250
        water.measureUnit = "ml"
        context.insert(water)

        XCTAssertNil(ActivityStore.shared.addRecord(water, on: .now, count: 2, minutes: 0, context: context))
        XCTAssertEqual(try logs(water).map(\.amount), [250, 250])
    }

    func testPastDayIsRecordedAtNoon() throws {
        let book = KeyObject(name: "책", emoji: "📚", action: .session, threshold: 0.6)
        context.insert(book)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: .now)!

        XCTAssertNil(ActivityStore.shared.addRecord(book, on: threeDaysAgo, minutes: 20, context: context))
        let log = try XCTUnwrap(try logs(book).first)
        XCTAssertTrue(calendar.isDate(log.startedAt, inSameDayAs: threeDaysAgo))
        XCTAssertEqual(calendar.component(.hour, from: log.startedAt), 12)
        XCTAssertEqual(log.duration, 20 * 60)
    }

    func testCountdownLeavesNoRecord() throws {
        let rest = KeyObject(name: "휴식", emoji: "☕️", action: .countdown(minutes: 5), threshold: 0.6)
        context.insert(rest)

        XCTAssertNotNil(ActivityStore.shared.addRecord(rest, on: .now, minutes: 5, context: context))
        XCTAssertTrue(try logs(rest).isEmpty)
    }
}

enum AppTestStore {
    /// 앱과 같은 스키마의 메모리 저장소. 테스트마다 새로 만든다.
    static func make() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppModel.types), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
