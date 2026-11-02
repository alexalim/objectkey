import Foundation
import ObjectKeyCore

/// 자연어 질문에 답할 근거. 이미 테스트된 계산으로 숫자를 미리 만들어 두고, 모델은 문장만 다듬는다.
@MainActor
enum HabitFacts {
    static func text(keys: [KeyObject], logs: [ActivityLog], notes: [DayNote], state: ObjectKeyCore.ActivityState) -> String {
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let dayFormat = Date.FormatStyle().month(.defaultDigits).day()
        var lines = ["오늘: \(now.formatted(.dateTime.year().month().day().weekday(.wide)))"]
        for key in keys {
            let mine = logs.filter { $0.keyID == key.id }
            guard key.supportsGoal else {
                lines.append("- \(key.name): \(key.action.label), 기록 \(mine.count)회")
                continue
            }
            let entries = KeyProgress.entries(key, logs: mine, state: state, now: now)
            let p = DailyProgress.evaluate(entries, goal: key.goalAmount, schedule: key.schedule, now: now, calendar: calendar)
            let best = DailyProgress.bestStreak(entries, goal: key.goalAmount, schedule: key.schedule, now: now, calendar: calendar)
            let began = min(key.createdAt, mine.map(\.startedAt).min() ?? key.createdAt)
            let rate = DailyProgress.completionRate(entries, goal: key.goalAmount, schedule: key.schedule,
                                                    since: max(monthStart, began), now: now, calendar: calendar)
            let days = DailyProgress.days(entries, goal: key.goalAmount, calendar: calendar)
            let monthLogs = mine.filter { $0.startedAt >= monthStart }
            let amount = key.actionKind == "counter" ? "이번 달 \(monthLogs.count)회"
                : "이번 달 \(Int(monthLogs.reduce(0) { $0 + $1.duration } / 60))분(\(monthLogs.count)회)"
            let recent = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) }
                .map { "\($0.formatted(dayFormat)) \(days[$0] == .met ? "함" : "안 함")" }
            let tagText = key.tags.isEmpty ? "" : ", 태그 " + key.tags.map { "#\($0)" }.joined(separator: " ")
            var line = "- \(key.name)(\(key.action.label), \(key.schedule.label)\(tagText)): 오늘 \(p.metToday ? "함" : "아직"), "
                + "지금 \(p.streak)일째, 최고 \(best)일, 이번 달 완료율 \(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "없음"), "
                + "\(amount), 전체 \(mine.count)회, 이번 주 \(p.weekDone)일. 최근 7일: \(recent.joined(separator: ", "))"
            let memo = notes.filter { $0.keyID == key.id }.sorted { $0.day > $1.day }.prefix(3)
            if !memo.isEmpty { line += ". 메모: " + memo.map { "\($0.day.formatted(dayFormat)) \($0.text)" }.joined(separator: "; ") }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
