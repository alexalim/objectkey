import Foundation

/// 습관 레벨. 습관 힘(0...1)을 네 단계로 나눈다. 경계는 습관 힘 설명 문구(0.2·0.5·0.8)와 같다.
/// 습관 힘은 놓친 날 조금 내려가므로 레벨도 내려갈 수 있다. 내려갈 때는 따로 알리지 않는다.
public enum HabitLevel {
    public static let bounds: [Double] = [0, 0.2, 0.5, 0.8]
    public static var maxLevel: Int { bounds.count }

    /// 레벨(1부터)과 다음 레벨까지 채운 비율. 가장 높은 레벨이면 비율은 nil.
    public static func of(score: Double) -> (level: Int, progress: Double?) {
        let s = min(max(score, 0), 1)
        let index = bounds.lastIndex { s >= $0 } ?? 0
        guard index + 1 < bounds.count else { return (index + 1, nil) }
        let low = bounds[index], high = bounds[index + 1]
        return (index + 1, (s - low) / (high - low))
    }
}

/// 완료 화면의 칭찬 한 줄. 지금 상황에 가장 맞는 말 하나를 고른다.
/// 습관 이름 뒤에 조사를 붙이지 않도록 이름은 넣지 않는다(이름은 화면에 따로 보인다).
public enum Praise {
    public struct Moment: Equatable, Sendable {
        public var isQuit = false
        /// 이 습관의 첫 기록인지.
        public var isFirst = false
        /// 마지막 기록부터 오늘까지 지난 날 수. 기록이 없었으면 nil.
        public var daysSinceLast: Int?
        /// 기록 전, 이번에 안 하면 끊기는 상태였는지.
        public var wasAtRisk = false
        public var streakAfter = 0
        public var allDoneToday = false
        public var levelBefore = 1
        public var levelAfter = 1
        /// 이번에 새 스티커를 받았는지. 받았으면 그 카드가 축하하므로 일수 축하는 겹치지 않게 뺀다.
        public var newSticker = false

        public init(isQuit: Bool = false, isFirst: Bool = false, daysSinceLast: Int? = nil, wasAtRisk: Bool = false,
                    streakAfter: Int = 0, allDoneToday: Bool = false, levelBefore: Int = 1, levelAfter: Int = 1, newSticker: Bool = false) {
            self.isQuit = isQuit; self.isFirst = isFirst; self.daysSinceLast = daysSinceLast; self.wasAtRisk = wasAtRisk
            self.streakAfter = streakAfter; self.allDoneToday = allDoneToday
            self.levelBefore = levelBefore; self.levelAfter = levelAfter; self.newSticker = newSticker
        }
    }

    /// 며칠 만에 다시 하면 "돌아왔다"고 말할지.
    public static let comebackDays = 3

    public static func message(_ m: Moment) -> String {
        if m.isQuit { return "기록했어요. 내일 다시 지켜 봐요." }
        if m.isFirst { return "첫 기록이에요! 시작이 반이에요." }
        if let gap = m.daysSinceLast, gap >= comebackDays { return "다시 돌아왔어요. 오늘부터 다시 쌓아요." }
        if m.wasAtRisk { return "아슬아슬했는데 이어 갔어요!" }
        if m.levelAfter > m.levelBefore { return "습관 레벨이 올랐어요! Lv.\(m.levelAfter)" }
        if m.allDoneToday { return "오늘 할 일을 모두 끝냈어요!" }
        if !m.newSticker, Milestones.streakDays.contains(m.streakAfter), m.streakAfter > 1 {
            return "\(m.streakAfter)일째예요! 꾸준함이 쌓이고 있어요."
        }
        return "좋아요! 오늘의 작은 약속 하나 완료."
    }
}
