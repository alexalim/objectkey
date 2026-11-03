import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 단계별 루틴: 저장 형식, 흐른 시간 → 지금 단계, 다가올 단계 경계.
final class RoutineTests: XCTestCase {
    private let steps = [RoutineStep(name: "세수", minutes: 3), RoutineStep(name: "양치", minutes: 2), RoutineStep(name: "스트레칭", minutes: 5)]
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_storedFormat_roundTripsAndSkipsBadLines() {
        XCTAssertEqual(Routine.steps(steps.map(\.stored)), steps)
        XCTAssertEqual(Routine.steps(["|3", "세수|0", "양치|x", "물 마시기|1"]), [RoutineStep(name: "물 마시기", minutes: 1)])
        XCTAssertEqual(Routine.totalMinutes(steps), 10)
    }

    func test_progress_followsElapsedTime() {
        XCTAssertEqual(Routine.progress(steps, elapsed: 0), RoutineProgress(index: 0, remaining: 180, isFinished: false))
        XCTAssertEqual(Routine.progress(steps, elapsed: 200), RoutineProgress(index: 1, remaining: 100, isFinished: false))
        XCTAssertEqual(Routine.progress(steps, elapsed: 300).index, 2, "경계 시각에는 다음 단계")
        XCTAssertTrue(Routine.progress(steps, elapsed: 600).isFinished)
    }

    func test_upcomingBoundaries_skipPast_andEndWithNil() {
        let next = Routine.upcomingBoundaries(steps, runStart: t0, now: t0.addingTimeInterval(200))
        XCTAssertEqual(next.map { $0.at.timeIntervalSince(t0) }, [300, 600])
        XCTAssertEqual(next.map { $0.next?.name }, ["스트레칭", nil])
    }
}
