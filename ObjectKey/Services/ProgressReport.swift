import Foundation
import ObjectKeyCore

extension KeyProgress {
    /// 기록과 진행 중(또는 휴식으로 멈춰 둔) 세션에서 이 물건의 오늘 진행·연속 일수를 구한다.
    static func of(_ key: KeyObject, logs: [ActivityLog], state: ActivityState, now: Date = .now) -> KeyProgress {
        DailyProgress.evaluate(entries(key, logs: logs, state: state, now: now), goal: key.goalAmount, now: now, calendar: .current)
    }

    /// 이 물건의 기록을 날짜·양으로 바꾼다. 진행 중이거나 멈춰 둔 세션은 지금 시각의 기록으로 더한다.
    static func entries(_ key: KeyObject, logs: [ActivityLog], state: ActivityState, now: Date = .now) -> [ProgressEntry] {
        var entries = logs.filter { $0.keyID == key.id }.map {
            ProgressEntry(date: $0.startedAt, amount: $0.kind == "counter" ? 1 : $0.duration)
        }
        switch state {
        case .session(let id, _, let segmentStart, let accumulated) where id == key.id:
            entries.append(ProgressEntry(date: now, amount: accumulated + now.timeIntervalSince(segmentStart)))
        case .countdown(_, _, let paused?) where paused.keyID == key.id:
            entries.append(ProgressEntry(date: now, amount: paused.accumulated))
        default:
            break
        }
        return entries
    }

    /// "20/30분", "3/8회", 목표 없으면 "20분"·"3회".
    func summary(forCounter counter: Bool) -> String {
        let unit = counter ? "회" : "분"
        let value = counter ? Int(today) : Int(today / 60)
        if let goal {
            return "\(value)/\(counter ? Int(goal) : Int(goal / 60))\(unit)"
        }
        return "\(value)\(unit)"
    }
}
