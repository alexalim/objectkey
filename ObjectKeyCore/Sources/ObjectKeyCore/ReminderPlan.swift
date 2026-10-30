import Foundation

/// 습관 알림 예약 시각.
///
/// 매일 반복 알림은 "오늘 이미 했으면 건너뛰기"를 할 수 없다. 그래서 앞으로 며칠 치를 한 번짜리로 예약하고,
/// 앱을 열거나 기록할 때마다 다시 계산한다. 오늘 이미 채웠거나 시각이 지났으면 오늘 알림은 빠진다.
public enum ReminderPlan {
    /// - Parameters:
    ///   - minuteOfDay: 자정부터 분(0...1439).
    ///   - days: 오늘부터 며칠 치를 만들지.
    public static func fireDates(minuteOfDay: Int, metToday: Bool, days: Int, now: Date, calendar: Calendar) -> [Date] {
        guard (0..<24 * 60).contains(minuteOfDay), days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset -> Date? in
            if offset == 0, metToday { return nil }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day),
                  fire > now else { return nil }
            return fire
        }
    }
}
