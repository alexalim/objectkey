import Foundation

/// 습관 힘. 해야 하는 날마다 채웠으면 1, 놓쳤으면 0을 조금씩 섞는 점수(0...1).
/// 한두 번 놓쳐도 갑자기 0이 되지 않고, 꾸준하면 천천히 오른다. Loop Habit Tracker의 공개 공식과 같은 방식이다:
/// multiplier = 0.5^(√빈도 / 13), 점수 = 이전 점수 × multiplier + 그날 값 × (1 − multiplier).
/// 매일 하는 습관이면 하루 반영이 약 5%라, 13일쯤 지나면 이전 점수의 영향이 절반이 된다.
public enum HabitStrength {
    public struct Point: Equatable, Sendable {
        public let day: Date
        public let score: Double
    }

    /// since부터 오늘까지 날마다의 점수. 진행 중인 오늘은 채웠을 때만 반영한다(아침마다 떨어지지 않게).
    public static func series(_ entries: [ProgressEntry], goal: Double?, schedule: HabitSchedule, skipped: Set<Date> = [],
                              since: Date, now: Date, calendar: Calendar) -> [Point] {
        let goal = goal.flatMap { $0 > 0 ? $0 : nil }
        let totals = DailyProgress.dailyTotals(entries, calendar: calendar)
        func met(_ day: Date) -> Bool {
            let total = totals[day] ?? 0
            return goal.map { total >= $0 } ?? (total > 0)
        }
        let frequency: Double = switch schedule {
        case .daily: 1
        case .weekdays(let days): days.isEmpty ? 1 : Double(days.count) / 7
        case .perWeek(let n): Double(max(1, min(n, 7))) / 7
        }
        let multiplier = pow(0.5, frequency.squareRoot() / 13)
        let due = DailyProgress.dueCheck(schedule, skipped: skipped, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        var points: [Point] = []
        var score = 0.0
        var day = calendar.startOfDay(for: since)
        while day <= today {
            let value: Double?
            switch schedule {
            case .perWeek(let n):
                // 요일이 정해지지 않았으니 날마다 "최근 7일 중 채운 날 / N"을 섞는다. 건너뛴 날은 그대로 둔다.
                if skipped.contains(day) {
                    value = nil
                } else {
                    let window = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
                    value = min(1, Double(window.filter(met).count) / Double(max(1, n)))
                }
            case .daily, .weekdays:
                value = due(day) ? (met(day) ? 1 : 0) : nil
            }
            if let value, day < today || met(day) {
                score = score * multiplier + value * (1 - multiplier)
            }
            points.append(Point(day: day, score: score))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }
}

/// 지난 기간과 비교. "지난 30일보다 4번 더 했어요"에 쓴다.
public enum PeriodCompare {
    /// 최근 days일과 그 앞 days일에 채운 날 수. 오늘이 최근 기간의 마지막 날이다.
    public static func metDays(_ entries: [ProgressEntry], goal: Double?, days: Int, now: Date,
                               calendar: Calendar) -> (recent: Int, previous: Int) {
        let today = calendar.startOfDay(for: now)
        guard let recentStart = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -days, to: recentStart) else { return (0, 0) }
        let metDays = DailyProgress.days(entries, goal: goal, calendar: calendar).filter { $0.value == .met }.keys
        return (metDays.filter { $0 >= recentStart && $0 <= today }.count,
                metDays.filter { $0 >= previousStart && $0 < recentStart }.count)
    }
}
