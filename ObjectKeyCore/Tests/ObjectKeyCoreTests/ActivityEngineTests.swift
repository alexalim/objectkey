import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 스캔 결과 → 동작 상태 전이. 시간은 주입해 결정적으로 검증한다.
final class ActivityEngineTests: XCTestCase {
    private let book = UUID()
    private let brush = UUID()
    private let mug = UUID()
    private let tally = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private var actions: [UUID: KeyAction] {
        [book: .session, brush: .session, mug: .countdown(minutes: 5), tally: .counter]
    }

    private func match(_ id: UUID) -> ScanOutcome { .match(Candidate(keyID: id, distance: 0.1)) }
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: 미확인 오실행 0건 (기획서 검증 지표)

    func test_noMatch_neverChangesStateOrProducesEffects() {
        var engine = ActivityEngine()
        XCTAssertEqual(engine.handle(.noMatch, actions: actions, now: t0), .notRecognized)
        XCTAssertEqual(engine.state, .idle)
    }

    func test_ambiguous_asksForChoiceWithoutExecuting() {
        var engine = ActivityEngine()
        let outcome = ScanOutcome.ambiguous([Candidate(keyID: book, distance: 0.2), Candidate(keyID: brush, distance: 0.21)])
        XCTAssertEqual(engine.handle(outcome, actions: actions, now: t0), .needsChoice([book, brush]))
        XCTAssertEqual(engine.state, .idle)
    }

    func test_matchForDeletedKey_isNotRecognized() {
        var engine = ActivityEngine()
        XCTAssertEqual(engine.handle(match(UUID()), actions: actions, now: t0), .notRecognized)
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: 세션 토글

    func test_sameObjectTwice_startsThenRecordsSession() {
        var engine = ActivityEngine()
        XCTAssertEqual(engine.handle(match(book), actions: actions, now: t0), .executed([.feedback(.started)]))
        let stop = engine.handle(match(book), actions: actions, now: at(600))
        XCTAssertEqual(stop, .executed([.recordSession(keyID: book, startedAt: t0, duration: 600), .feedback(.stopped)]))
        XCTAssertEqual(engine.state, .idle)
    }

    func test_otherSessionWhileRunning_requiresConfirmation_thenSwitches() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        let res = engine.handle(match(brush), actions: actions, now: at(100))
        guard case .needsConfirmation(let pending) = res else { return XCTFail("\(res)") }
        XCTAssertEqual(engine.state.activeKeyID, book)   // 확인 전에는 그대로

        let effects = engine.confirm(pending, now: at(120))
        XCTAssertEqual(effects, [
            .recordSession(keyID: book, startedAt: t0, duration: 120),
            .feedback(.stopped),
            .feedback(.started),
        ])
        XCTAssertEqual(engine.state.activeKeyID, brush)
    }

    func test_staleConfirmation_isIgnored() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        guard case .needsConfirmation(let pending) = engine.handle(match(brush), actions: actions, now: at(10)) else {
            return XCTFail()
        }
        _ = engine.handle(match(book), actions: actions, now: at(20))   // 그 사이 세션 종료
        XCTAssertEqual(engine.confirm(pending, now: at(30)), [])
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: 휴식(카운트다운)

    func test_breakDuringSession_pausesWithoutConfirmation_andExcludesBreakTime() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        let res = engine.handle(match(mug), actions: actions, now: at(600))
        XCTAssertEqual(res, .executed([.scheduleCountdownEnd(keyID: mug, at: at(900)), .feedback(.started)]))

        XCTAssertEqual(engine.tick(now: at(899)), [])
        XCTAssertEqual(engine.tick(now: at(900)), [.feedback(.countdownFinished)])
        XCTAssertEqual(engine.state.activeKeyID, book)   // 세션 재개

        let stop = engine.handle(match(book), actions: actions, now: at(1200))
        // 600초 + 휴식 후 300초 = 900초 (휴식 300초 제외)
        XCTAssertEqual(stop, .executed([.recordSession(keyID: book, startedAt: t0, duration: 900), .feedback(.stopped)]))
    }

    func test_scanBreakObjectAgain_endsBreakEarlyAndResumes() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        _ = engine.handle(match(mug), actions: actions, now: at(60))
        XCTAssertEqual(engine.handle(match(mug), actions: actions, now: at(90)),
                       .executed([.cancelCountdownEnd, .feedback(.stopped)]))
        XCTAssertEqual(engine.state, .session(keyID: book, startedAt: t0, segmentStart: at(90), accumulated: 60))
    }

    func test_breakWithoutSession_endsToIdle() {
        var engine = ActivityEngine()
        _ = engine.handle(match(mug), actions: actions, now: t0)
        XCTAssertEqual(engine.tick(now: at(300)), [.feedback(.countdownFinished)])
        XCTAssertEqual(engine.state, .idle)
    }

    func test_sessionScanDuringBreak_confirmationRecordsPausedSession() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        _ = engine.handle(match(mug), actions: actions, now: at(60))
        guard case .needsConfirmation(let pending) = engine.handle(match(brush), actions: actions, now: at(70)) else {
            return XCTFail()
        }
        XCTAssertEqual(engine.confirm(pending, now: at(70)), [
            .cancelCountdownEnd,
            .recordSession(keyID: book, startedAt: t0, duration: 60),
            .feedback(.stopped),
            .feedback(.started),
        ])
    }

    func test_lateTick_resumesSessionFromBreakEnd_notFromNow() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        _ = engine.handle(match(mug), actions: actions, now: at(600))   // 휴식 종료 at(900)
        XCTAssertEqual(engine.tick(now: at(1500)), [.feedback(.countdownFinished)])
        let stop = engine.handle(match(book), actions: actions, now: at(1800))
        // 600초 + (1800-900)초 = 1500초. 휴식 300초만 빠진다.
        XCTAssertEqual(stop, .executed([.recordSession(keyID: book, startedAt: t0, duration: 1500), .feedback(.stopped)]))
    }

    func test_scanAfterExpiredBreakWithoutTick_stopsSessionWithoutConfirmation() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        _ = engine.handle(match(mug), actions: actions, now: at(600))
        let stop = engine.handle(match(book), actions: actions, now: at(1200))
        XCTAssertEqual(stop, .executed([
            .feedback(.countdownFinished),
            .recordSession(keyID: book, startedAt: t0, duration: 900),
            .feedback(.stopped),
        ]))
        XCTAssertEqual(engine.state, .idle)
    }

    func test_finish_recordsPausedSessionDuringBreak_andInvolvesPausedKey() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        _ = engine.handle(match(mug), actions: actions, now: at(60))
        XCTAssertTrue(engine.state.involves(book))
        XCTAssertTrue(engine.state.involves(mug))
        XCTAssertFalse(engine.state.involves(brush))
        XCTAssertEqual(engine.finish(now: at(100)), [
            .cancelCountdownEnd,
            .recordSession(keyID: book, startedAt: t0, duration: 60),
            .feedback(.stopped),
        ])
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.finish(now: at(200)), [])
    }

    // MARK: 카운터

    func test_counter_neverTouchesRunningSession() {
        var engine = ActivityEngine()
        _ = engine.handle(match(book), actions: actions, now: t0)
        XCTAssertEqual(engine.handle(match(tally), actions: actions, now: at(5)),
                       .executed([.incrementCounter(keyID: tally, at: at(5)), .feedback(.counted)]))
        XCTAssertEqual(engine.state.activeKeyID, book)
    }

    func test_state_roundTripsThroughJSON() throws {
        let state = ActivityState.countdown(keyID: mug, endsAt: t0,
                                            paused: PausedSession(keyID: book, startedAt: t0, accumulated: 42))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(ActivityState.self, from: data), state)
    }
}
