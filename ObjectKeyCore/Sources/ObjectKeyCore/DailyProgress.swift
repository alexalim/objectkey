import Foundation

/// 하루 목표와 연속 일수 계산. 날짜 경계는 호출자가 준 Calendar를 따른다.
public struct ProgressEntry: Equatable, Sendable {
    public var date: Date
    /// 세션은 초, 카운터는 횟수.
    public var amount: Double

    public init(date: Date, amount: Double) {
        self.date = date
        self.amount = amount
    }
}

public struct KeyProgress: Equatable, Sendable {
    public var today: Double
    /// nil이면 목표 없음. 그때는 하루에 한 번이라도 기록되면 그 날을 채운 것으로 본다.
    public var goal: Double?
    public var streak: Int

    public init(today: Double, goal: Double?, streak: Int) {
        self.today = today
        self.goal = goal
        self.streak = streak
    }

    public var metToday: Bool { goal.map { today >= $0 } ?? (today > 0) }
    /// 목표 대비 오늘 진행률 (0...1). 목표가 없으면 nil.
    public var fraction: Double? { goal.map { min(1, today / $0) } }
}

public enum DailyProgress {
    /// 같은 날 기록을 합산하고, 조건을 채운 날이 오늘(또는 어제)까지 며칠 이어졌는지 센다.
    /// 오늘을 아직 못 채웠으면 어제까지의 연속 일수를 돌려준다. 오늘 안에 채우면 이어진다.
    public static func evaluate(_ entries: [ProgressEntry], goal: Double?, now: Date, calendar: Calendar) -> KeyProgress {
        let goal = goal.flatMap { $0 > 0 ? $0 : nil }
        var totals: [Date: Double] = [:]
        for entry in entries {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.amount
        }
        func met(_ day: Date) -> Bool {
            let total = totals[day] ?? 0
            return goal.map { total >= $0 } ?? (total > 0)
        }

        let today = calendar.startOfDay(for: now)
        var streak = 0
        var day: Date? = met(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)
        while let d = day, met(d) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: d)
        }
        return KeyProgress(today: totals[today] ?? 0, goal: goal, streak: streak)
    }
}
