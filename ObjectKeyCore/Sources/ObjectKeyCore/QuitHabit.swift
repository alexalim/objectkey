import Foundation

/// "끊기" 습관. 저지른 날(실수)만 기록하고, 기록이 없는 날을 지킨 날로 센다.
/// 지킨 날을 일반 기록처럼 만들어 넘기면 연속 일수·완료율·달력·통계 계산을 그대로 쓸 수 있다.
public enum QuitHabit {
    /// 너무 오래된 시작일 때문에 계산이 느려지지 않게, 최근 이만큼만 본다.
    public static let maxDays = 400

    /// 시작한 날부터 오늘까지, 실수가 없는 날마다 하루 1의 기록을 만든다.
    /// 오늘은 아직 끝나지 않았지만 실수가 없으면 지킨 것으로 본다(하루 종일 ○로 보이지 않게).
    public static func cleanDays(slips: [Date], since start: Date, now: Date, calendar: Calendar) -> [ProgressEntry] {
        let today = calendar.startOfDay(for: now)
        var day = max(calendar.startOfDay(for: start),
                      calendar.date(byAdding: .day, value: -(maxDays - 1), to: today) ?? today)
        let slipDays = Set(slips.map { calendar.startOfDay(for: $0) })
        var entries: [ProgressEntry] = []
        while day <= today {
            if !slipDays.contains(day) { entries.append(ProgressEntry(date: day.addingTimeInterval(12 * 3600), amount: 1)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return entries
    }
}
