import Foundation
import UserNotifications
import ObjectKeyCore

/// 습관 알림 예약. 계산은 ReminderPlan, 여기서는 알림 센터에 넣고 빼기만 한다.
@MainActor
enum HabitReminders {
    private static let prefix = "objectkey.habit."
    /// iOS는 앱당 대기 알림을 64개까지만 둔다. 휴식 타이머 몫을 남긴다.
    private static let budget = 60

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 기존 습관 알림을 모두 지우고 다시 예약한다. 앱을 열 때, 기록이 생길 때, 설정을 바꿀 때 부른다.
    static func reschedule(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let targets = keys.filter { $0.supportsGoal && $0.reminderMinute >= 0 }
        guard !targets.isEmpty, await center.notificationSettings().authorizationStatus == .authorized else { return }
        let days = min(7, budget / targets.count)
        let calendar = Calendar.current
        let now = Date.now
        for key in targets {
            let progress = KeyProgress.of(key, logs: logs, state: state, now: now)
            let dates = ReminderPlan.fireDates(minuteOfDay: key.reminderMinute, metToday: progress.metToday,
                                               days: days, now: now, calendar: calendar)
            for (i, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = key.name
                content.body = body(for: key, progress: progress, today: calendar.isDate(date, inSameDayAs: now))
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(key.id.uuidString).\(i)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    /// 오늘 알림만 현재 연속 일수를 안다. 이후 날짜는 그날 상태를 모르므로 일반 문구를 쓴다.
    private static func body(for key: KeyObject, progress: KeyProgress, today: Bool) -> String {
        if today, progress.atRisk { return "어제 쉬었어요. 오늘 비추면 \(progress.streak)일이 이어져요." }
        let cue = key.cue.trimmingCharacters(in: .whitespaces)
        return cue.isEmpty ? "비춰 볼 시간이에요. 작게라도 충분해요." : "\(cue) 다음에 비춰 볼 시간이에요."
    }
}
