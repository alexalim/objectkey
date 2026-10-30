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

/// 66일 습관 형성 단계 (UCL Lally 연구의 평균 66일을 3구간으로 나눈 것).
public enum HabitPhase: Equatable, Sendable {
    /// 1~22일: 뇌가 저항하는 시기. 작게라도 시작하는 것이 목표.
    case adapting
    /// 23~44일: 새 회로가 연결되는 시기. 쉬는 날에도 이어가는 것이 핵심.
    case wiring
    /// 45~66일: 의식하지 않아도 몸이 먼저 움직이는 시기.
    case automating
    /// 66일을 넘김.
    case formed

    public init?(day: Int) {
        switch day {
        case ..<1: return nil
        case 1...22: self = .adapting
        case 23...44: self = .wiring
        case 45...66: self = .automating
        default: self = .formed
        }
    }
}

public struct KeyProgress: Equatable, Sendable {
    public var today: Double
    /// nil이면 목표 없음. 그때는 하루에 한 번이라도 기록되면 그 날을 채운 것으로 본다.
    public var goal: Double?
    /// 이어가고 있는 습관에서 조건을 채운 날 수. 하루 빠진 날은 세지 않지만 끊지도 않는다.
    public var streak: Int
    /// 어제를 빠졌고 오늘도 아직 못 채웠다. 오늘 안 하면 끊긴다.
    public var atRisk: Bool

    public init(today: Double, goal: Double?, streak: Int, atRisk: Bool = false) {
        self.today = today
        self.goal = goal
        self.streak = streak
        self.atRisk = atRisk
    }

    public var metToday: Bool { goal.map { today >= $0 } ?? (today > 0) }
    /// 목표 대비 오늘 진행률 (0...1). 목표가 없으면 nil.
    public var fraction: Double? { goal.map { min(1, today / $0) } }
    /// 이어온 일수 기준 66일 단계. 아직 시작 전이면 nil.
    public var phase: HabitPhase? { HabitPhase(day: streak) }
}

public enum DailyProgress {
    /// 같은 날 기록을 합산하고, 조건을 채운 날이 얼마나 이어졌는지 센다.
    ///
    /// 이틀 규칙: 하루 빠진 것은 습관 형성에 큰 지장이 없으므로 끊지 않고, 이틀 연속 빠지면 끊는다.
    /// 오늘은 하루가 끝나기 전이라 빠진 날로 보지 않는다.
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
        func previous(_ day: Date) -> Date? { calendar.date(byAdding: .day, value: -1, to: day) }

        let today = calendar.startOfDay(for: now)
        let todayTotal = totals[today] ?? 0
        guard let earliest = totals.keys.min(), let yesterday = previous(today) else {
            return KeyProgress(today: todayTotal, goal: goal, streak: 0)
        }

        var streak = 0
        var misses = 0
        var day: Date? = met(today) ? today : yesterday
        while let d = day, d >= earliest {
            if met(d) {
                streak += 1
                misses = 0
            } else {
                misses += 1
                if misses >= 2 { break }
            }
            day = previous(d)
        }
        let atRisk = streak > 0 && !met(today) && !met(yesterday)
        return KeyProgress(today: todayTotal, goal: goal, streak: streak, atRisk: atRisk)
    }
}
