import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 건강 앱에 쓸 기록 고르기(읽기·쓰기 되먹임 막기 포함).
final class HealthWriteTests: XCTestCase {
    private let id = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func test_session_isWritten() {
        let s = HealthWrite.sample(keyID: id, writeTarget: "mindful", readMetric: "", logKind: "session", start: start, duration: 600)
        XCTAssertEqual(s?.target, .mindful)
        XCTAssertEqual(s?.end, start.addingTimeInterval(600))
        XCTAssertEqual(s?.syncID, HealthWrite.syncID(keyID: id, start: start))
    }

    func test_habitThatReadsHealth_isNotWritten() {
        XCTAssertNil(HealthWrite.sample(keyID: id, writeTarget: "mindful", readMetric: "mindfulMinutes",
                                        logKind: "session", start: start, duration: 600))
    }

    func test_nonSessionLogs_areNotWritten() {
        for kind in ["health", "counter"] {
            XCTAssertNil(HealthWrite.sample(keyID: id, writeTarget: "running", readMetric: "", logKind: kind, start: start, duration: 600), kind)
        }
    }

    func test_shortOrUnsetOrUnknown_areNotWritten() {
        XCTAssertNil(HealthWrite.sample(keyID: id, writeTarget: "yoga", readMetric: "", logKind: "session", start: start, duration: 30))
        XCTAssertNil(HealthWrite.sample(keyID: id, writeTarget: "", readMetric: "", logKind: "session", start: start, duration: 600))
        XCTAssertNil(HealthWrite.sample(keyID: id, writeTarget: "swim", readMetric: "", logKind: "session", start: start, duration: 600))
    }

    func test_syncID_isStablePerKeyAndStart() {
        XCTAssertEqual(HealthWrite.syncID(keyID: id, start: start), HealthWrite.syncID(keyID: id, start: start.addingTimeInterval(0.4)))
        XCTAssertNotEqual(HealthWrite.syncID(keyID: id, start: start), HealthWrite.syncID(keyID: UUID(), start: start))
    }

    func test_workoutTargets() {
        XCTAssertFalse(HealthWriteTarget.mindful.isWorkout)
        XCTAssertTrue(HealthWriteTarget.allCases.filter { $0 != .mindful }.allSatisfy(\.isWorkout))
    }
}
