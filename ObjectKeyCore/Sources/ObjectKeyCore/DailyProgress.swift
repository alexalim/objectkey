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
    /// 직전 기회를 놓쳤고 이번 기회도 아직 못 채웠다. 이번에 안 하면 끊긴다.
    /// 매일·요일 지정은 오늘, 주 N회는 이번 주가 기회다.
    public var atRisk: Bool
    /// 이번 주에 채운 날 수. 주 N회 표시에 쓴다.
    public var weekDone: Int

    public init(today: Double, goal: Double?, streak: Int, atRisk: Bool = false, weekDone: Int = 0) {
        self.today = today
        self.goal = goal
        self.streak = streak
        self.atRisk = atRisk
        self.weekDone = weekDone
    }

    public var metToday: Bool { goal.map { today >= $0 } ?? (today > 0) }
    /// 목표 대비 오늘 진행률 (0...1). 목표가 없으면 nil.
    public var fraction: Double? { goal.map { min(1, today / $0) } }
    /// 이어온 일수 기준 66일 단계. 아직 시작 전이면 nil.
    public var phase: HabitPhase? { HabitPhase(day: streak) }
}

/// 언제 해야 하는 습관인가.
public enum HabitSchedule: Equatable, Sendable {
    case daily
    /// 정한 요일만. Calendar weekday 값(1=일요일 … 7=토요일).
    case weekdays(Set<Int>)
    /// 일주일에 N일. 어느 요일이든 상관없다.
    case perWeek(Int)
}

/// 달력에 칠할 하루 상태.
public enum DayStatus: Equatable, Sendable {
    /// 조건을 채운 날. 연속 일수에 들어간다.
    case met
    /// 기록은 있지만 목표에 못 미친 날.
    case partial
}

public enum DailyProgress {
    /// 날짜(그날 0시)별 상태. 기록이 없는 날은 빠진다.
    public static func days(_ entries: [ProgressEntry], goal: Double?, calendar: Calendar) -> [Date: DayStatus] {
        let goal = goal.flatMap { $0 > 0 ? $0 : nil }
        return dailyTotals(entries, calendar: calendar).compactMapValues { total in
            guard total > 0 else { return nil }
            return goal.map { total >= $0 } ?? true ? .met : .partial
        }
    }

    private static func dailyTotals(_ entries: [ProgressEntry], calendar: Calendar) -> [Date: Double] {
        var totals: [Date: Double] = [:]
        for entry in entries {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.amount
        }
        return totals
    }

    /// 같은 날 기록을 합산하고, 조건을 채운 날이 얼마나 이어졌는지 센다.
    ///
    /// 이틀 규칙: 한 번 빠진 것은 습관 형성에 큰 지장이 없으므로 끊지 않고, 두 번 연속 빠지면 끊는다.
    /// - 매일: 하루가 한 번. 요일 지정: 정한 요일만 한 번으로 보고, 다른 날에 한 것은 세되 빠져도 탓하지 않는다.
    /// - 주 N회: 한 주가 한 번. N일을 못 채운 주가 두 주 이어지면 끊는다.
    /// 일수는 어느 경우든 채운 날 수다. 진행 중인 오늘(이번 주)은 빠진 것으로 보지 않는다.
    public static func evaluate(_ entries: [ProgressEntry], goal: Double?, schedule: HabitSchedule = .daily,
                                now: Date, calendar: Calendar) -> KeyProgress {
        let goal = goal.flatMap { $0 > 0 ? $0 : nil }
        let totals = dailyTotals(entries, calendar: calendar)
        func met(_ day: Date) -> Bool {
            let total = totals[day] ?? 0
            return goal.map { total >= $0 } ?? (total > 0)
        }
        func previous(_ day: Date) -> Date? { calendar.date(byAdding: .day, value: -1, to: day) }

        let today = calendar.startOfDay(for: now)
        let todayTotal = totals[today] ?? 0
        let week = calendar.dateInterval(of: .weekOfYear, for: today)
        let weekDone = week.map { w in totals.keys.filter { w.contains($0) && met($0) }.count } ?? 0
        guard let earliest = totals.keys.min() else {
            return KeyProgress(today: todayTotal, goal: goal, streak: 0)
        }

        switch schedule {
        case .perWeek(let times):
            let target = max(1, times)
            // 이번 주는 채운 만큼 세되 빠진 것으로 보지 않고, 지난주부터 한 주씩 거슬러 간다.
            var streak = weekDone
            var misses = 0
            var missedDone = 0
            var lastWeekMissed = false
            var isLastWeek = true
            var start = week.flatMap { calendar.date(byAdding: .weekOfYear, value: -1, to: $0.start) }
            while let s = start, let w = calendar.dateInterval(of: .weekOfYear, for: s), w.end > earliest {
                let done = totals.keys.filter { w.contains($0) && met($0) }.count
                if done >= target {
                    misses = 0
                    missedDone = 0
                } else {
                    misses += 1
                    if isLastWeek { lastWeekMissed = true }
                    if misses >= 2 {
                        // 끊긴 두 주에 조금씩 한 날은 사슬 밖이다.
                        streak -= missedDone
                        break
                    }
                    missedDone = done
                }
                streak += done
                isLastWeek = false
                start = calendar.date(byAdding: .weekOfYear, value: -1, to: w.start)
            }
            let atRisk = streak > 0 && lastWeekMissed && weekDone < target
            return KeyProgress(today: todayTotal, goal: goal, streak: streak, atRisk: atRisk, weekDone: weekDone)

        case .daily, .weekdays:
            let due: (Date) -> Bool
            if case .weekdays(let days) = schedule, !days.isEmpty {
                due = { days.contains(calendar.component(.weekday, from: $0)) }
            } else {
                due = { _ in true }
            }
            var streak = met(today) ? 1 : 0
            var misses = 0
            var day = previous(today)
            while let d = day, d >= earliest {
                if met(d) {
                    streak += 1
                    misses = 0
                } else if due(d) {
                    misses += 1
                    if misses >= 2 { break }
                }
                day = previous(d)
            }
            // 오늘 해야 하는데 아직이고, 거슬러 올라가 처음 만나는 의미 있는 날이 놓친 날이면 오늘 안 하면 끊긴다.
            var lastChanceMissed = false
            day = previous(today)
            while let d = day, d >= earliest {
                if met(d) { break }
                if due(d) { lastChanceMissed = true; break }
                day = previous(d)
            }
            let atRisk = streak > 0 && due(today) && !met(today) && lastChanceMissed
            return KeyProgress(today: todayTotal, goal: goal, streak: streak, atRisk: atRisk, weekDone: weekDone)
        }
    }
}
