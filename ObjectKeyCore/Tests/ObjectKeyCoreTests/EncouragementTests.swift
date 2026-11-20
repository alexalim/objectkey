import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 습관 레벨 구간과 완료 칭찬 고르기 순서.
final class EncouragementTests: XCTestCase {
    func test_level_bandsMatchStrengthCaptions() {
        XCTAssertEqual(HabitLevel.of(score: 0).level, 1)
        XCTAssertEqual(HabitLevel.of(score: 0.1).progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(HabitLevel.of(score: 0.2).level, 2)
        XCTAssertEqual(HabitLevel.of(score: 0.35).progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(HabitLevel.of(score: 0.5).level, 3)
        XCTAssertEqual(HabitLevel.of(score: 0.79).level, 3)
        XCTAssertEqual(HabitLevel.of(score: 0.8).level, 4)
        XCTAssertNil(HabitLevel.of(score: 0.95).progress)
    }

    func test_level_clampsOutOfRange() {
        XCTAssertEqual(HabitLevel.of(score: -1).level, 1)
        XCTAssertEqual(HabitLevel.of(score: 2).level, HabitLevel.maxLevel)
    }

    func test_praise_priority() {
        // 끊기 습관은 저지른 기록이라 칭찬하지 않는다. 다른 조건이 모두 맞아도.
        XCTAssertEqual(Praise.message(.init(isQuit: true, isFirst: true, wasAtRisk: true, allDoneToday: true)),
                       "기록했어요. 내일 다시 지켜 봐요.")
        XCTAssertEqual(Praise.message(.init(isFirst: true, wasAtRisk: true)), "첫 기록이에요! 시작이 반이에요.")
        XCTAssertEqual(Praise.message(.init(daysSinceLast: 5, wasAtRisk: true)), "다시 돌아왔어요. 오늘부터 다시 쌓아요.")
        XCTAssertEqual(Praise.message(.init(daysSinceLast: 2, wasAtRisk: true, levelBefore: 1, levelAfter: 2)), "아슬아슬했는데 이어 갔어요!")
        XCTAssertEqual(Praise.message(.init(allDoneToday: true, levelBefore: 2, levelAfter: 3)), "습관 레벨이 올랐어요! Lv.3")
        XCTAssertEqual(Praise.message(.init(streakAfter: 7, allDoneToday: true)), "오늘 할 일을 모두 끝냈어요!")
    }

    func test_praise_milestoneDay_unlessStickerCelebrates() {
        XCTAssertEqual(Praise.message(.init(streakAfter: 7)), "7일째예요! 꾸준함이 쌓이고 있어요.")
        XCTAssertEqual(Praise.message(.init(streakAfter: 7, newSticker: true)), "좋아요! 오늘의 작은 약속 하나 완료.")
        XCTAssertEqual(Praise.message(.init(streakAfter: 8)), "좋아요! 오늘의 작은 약속 하나 완료.")
        // 1일째는 첫 스티커 날이라 일수 축하를 하지 않는다.
        XCTAssertEqual(Praise.message(.init(streakAfter: 1)), "좋아요! 오늘의 작은 약속 하나 완료.")
    }
}
