import Foundation
import SwiftData
import UserNotifications
import ObjectKeyCore

/// 습관 알림 예약. 계산은 ReminderPlan, 여기서는 알림 센터에 넣고 빼기만 한다.
@MainActor
enum HabitReminders {
    private static let prefix = "objectkey.habit."
    /// 참석 알림에 붙는 "참석" 버튼.
    static let attendCategory = "objectkey.attend"
    static let attendAction = "attend"
    /// iOS는 앱당 대기 알림을 64개까지만 둔다. 휴식 타이머 몫을 남긴다.
    private static let budget = 60

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 기존 습관 알림을 모두 지우고 다시 예약한다. 앱을 열 때, 기록이 생길 때, 설정을 바꿀 때 부른다.
    static func reschedule(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) async {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: attendCategory,
                                   actions: [UNNotificationAction(identifier: attendAction, title: "참석", options: [])],
                                   intentIdentifiers: []),
        ])
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
                                               days: days, now: now, calendar: calendar,
                                               isDue: isDue(key.schedule, progress: progress, now: now, calendar: calendar))
            for (i, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = key.name
                content.body = body(for: key, progress: progress, today: calendar.isDate(date, inSameDayAs: now))
                content.sound = .default
                if key.actionKind == "attend" {
                    content.categoryIdentifier = attendCategory
                    content.userInfo = ["keyID": key.id.uuidString]
                }
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(key.id.uuidString).\(i)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    private static func isDue(_ schedule: HabitSchedule, progress: KeyProgress, now: Date, calendar: Calendar) -> (Date) -> Bool {
        switch schedule {
        case .daily:
            return { _ in true }
        case .weekdays(let days):
            return { days.isEmpty || days.contains(calendar.component(.weekday, from: $0)) }
        case .perWeek(let n):
            // 이번 주를 이미 채웠으면 이번 주 남은 날은 조용히 둔다.
            guard progress.weekDone >= n, let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return { _ in true } }
            return { !week.contains($0) }
        }
    }

    /// 오늘 알림만 현재 연속 일수를 안다. 이후 날짜는 그날 상태를 모르므로 일반 문구를 쓴다.
    private static func body(for key: KeyObject, progress: KeyProgress, today: Bool) -> String {
        if today, progress.atRisk { return HabitCopy.risk(key.schedule, streak: progress.streak, weekDone: progress.weekDone) }
        if case .attend(let start, _) = key.action {
            let ahead = start - key.reminderMinute
            let when = ahead > 0 ? "\(ahead)분 뒤 \(KeyAction.clock(start))에 시작해요." : "\(KeyAction.clock(start))에 시작해요."
            return when + " 다녀오면 길게 눌러 '참석'을 눌러 주세요."
        }
        let cue = key.cue.trimmingCharacters(in: .whitespaces)
        return cue.isEmpty ? "비춰 볼 시간이에요. 작게라도 충분해요." : "\(cue) 다음에 비춰 볼 시간이에요."
    }

    /// 알림의 "참석" 버튼. 앱 화면 없이 실행되므로 공용 저장소와 진행 상태를 쓴다.
    static func recordAttendance(_ id: UUID) {
        let context = AppModel.container.mainContext
        guard let keys = try? context.fetch(FetchDescriptor<KeyObject>()),
              let key = keys.first(where: { $0.id == id }) else { return }
        _ = ActivityStore.shared.activate(key, keys: keys, context: context)
        WidgetBridge.refreshFromStore()
    }
}

/// 알림 버튼 처리와 앱이 열려 있을 때의 알림 표시.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == HabitReminders.attendAction,
              let raw = response.notification.request.content.userInfo["keyID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await HabitReminders.recordAttendance(id)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
