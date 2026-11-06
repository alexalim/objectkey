import Foundation
import Observation
import SwiftData
import UserNotifications
import ObjectKeyCore

/// 습관 알림 예약. 계산은 ReminderPlan, 여기서는 알림 센터에 넣고 빼기만 한다.
@MainActor
enum HabitReminders {
    private static let prefix = "objectkey.habit."
    /// 습관 알림에 붙는 버튼. 동작마다 이름만 다르고, 누르면 모두 위젯·단축어와 같은 길로 실행한다.
    static let attendCategory = "objectkey.attend"
    static let sessionCategory = "objectkey.session"
    static let counterCategory = "objectkey.counter"
    static let measureCategory = "objectkey.measure"
    /// 버튼 식별자. "attend"는 빌드 48 이전에 예약된 참석 알림이 쓰던 이름이라 그대로 둔다.
    static let attendAction = "attend"
    static let recordAction = "record"
    /// iOS는 앱당 대기 알림을 64개까지만 둔다. 휴식 타이머 몫을 남긴다.
    /// 휴식 타이머(1)와 단계별 루틴(최대 12)의 몫을 남긴다. 합이 64를 넘으면 iOS가 나중 알림을 버린다.
    private static let budget = 50

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 기존 습관 알림을 모두 지우고 다시 예약한다. 앱을 열 때, 기록이 생길 때, 설정을 바꿀 때 부른다.
    static func reschedule(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) async {
        let center = UNUserNotificationCenter.current()
        func withButton(_ id: String, _ title: String) -> UNNotificationCategory {
            UNNotificationCategory(identifier: id, actions: [UNNotificationAction(identifier: recordAction, title: title, options: [])],
                                   intentIdentifiers: [])
        }
        center.setNotificationCategories([
            withButton(attendCategory, "참석"), withButton(sessionCategory, "시작"),
            withButton(counterCategory, "+1"), withButton(measureCategory, "기록 추가"),
        ])
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        // 끊기 습관은 "할 시간"이 없으므로 알리지 않는다.
        let targets = keys.filter { $0.supportsGoal && !$0.isQuit && $0.reminderMinute >= 0 }
        guard !targets.isEmpty, await center.notificationSettings().authorizationStatus == .authorized else { return }
        let days = min(7, budget / targets.count)
        let calendar = Calendar.current
        let now = Date.now
        for key in targets {
            let progress = KeyProgress.of(key, logs: logs, state: state, now: now)
            // 마지막 기록(없으면 등록) 뒤 며칠이 지났는지. 오래 반응이 없으면 알림을 줄인다.
            let last = logs.filter { $0.keyID == key.id }.map(\.startedAt).max() ?? key.createdAt
            let idleDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
            let planned = ReminderPlan.fireDates(minuteOfDay: key.reminderMinute, metToday: progress.metToday,
                                               days: days, now: now, calendar: calendar,
                                               isDue: { day in
                                                   // 건너뛰기로 한 날은 알리지 않는다.
                                                   !key.isSkipped(day, calendar: calendar)
                                                       && isDue(key.schedule, progress: progress, now: now, calendar: calendar)(day)
                                               })
            let dates = ReminderPlan.thin(planned, idleDays: idleDays)
            for (i, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = key.name
                content.body = body(for: key, progress: progress, today: calendar.isDate(date, inSameDayAs: now),
                                    variant: calendar.ordinality(of: .day, in: .era, for: date) ?? i, idle: idleDays >= 7)
                content.sound = .default
                content.categoryIdentifier = category(for: key)
                content.userInfo = ["keyID": key.id.uuidString]
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(key.id.uuidString).\(i)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    private static func category(for key: KeyObject) -> String {
        switch key.kind {
        case .attend: attendCategory
        case .counter: key.measureStep > 0 ? measureCategory : counterCategory
        case .session, .countdown: sessionCategory
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
    /// 매일 같은 말이면 읽지 않게 된다. 날마다 돌려 쓴다.
    private static let nudges = [
        "할 시간이에요. 작게라도 충분해요.",
        "딱 한 번이면 돼요.",
        "오늘 몫을 하러 가 볼까요?",
        "짧게 해도 오늘로 쳐요.",
        "기다리고 있었어요. 가볍게 시작해요.",
    ]

    private static func body(for key: KeyObject, progress: KeyProgress, today: Bool, variant: Int, idle: Bool) -> String {
        if today, progress.atRisk { return HabitCopy.risk(key.schedule, streak: progress.streak, weekDone: progress.weekDone, quit: key.isQuit) }
        if case .attend(let start, _) = key.action {
            let ahead = start - key.reminderMinute
            let when = ahead > 0 ? "\(ahead)분 뒤 \(KeyAction.clock(start))에 시작해요." : "\(KeyAction.clock(start))에 시작해요."
            return when + " 다녀와서 알림을 길게 누르고 '참석'을 눌러 주세요."
        }
        // 한동안 쉬었으면 탓하지 않고 다시 시작해도 된다고만 말한다.
        if idle { return "언제든 다시 시작해도 돼요. 오늘 한 번이면 충분해요." }
        let cue = key.cue.trimmingCharacters(in: .whitespaces)
        if !cue.isEmpty, variant % 2 == 0 { return "\(cue) 다음에 할 시간이에요." }
        return nudges[abs(variant) % nudges.count]
    }

    /// 알림 버튼(참석·시작·+1). 위젯·단축어와 같은 길로 실행한다. 진행 중이던 다른 활동은 기록하고 넘어간다.
    /// 시간 기록이 이미 그 물건으로 진행 중이면 "시작"을 눌러도 멈추지 않게 그냥 둔다.
    static func recordFromNotification(_ id: UUID) {
        let store = ActivityStore.shared
        if case .session(let running, _, _, _) = store.state, running == id { return }
        store.runFromOutside(id)
    }
}

/// 일요일 저녁 "이번 주 돌아보기" 알림. 켜고 끌 수 있고, 누르면 통계 탭이 열린다.
enum WeeklyRecap {
    static let id = "objectkey.weekly-recap"
    static let enabledKey = "weeklyRecapEnabled"

    static func set(_ on: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard on, await HabitReminders.requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "이번 주 돌아보기"
        content.body = "한 주 동안 쌓은 기록을 볼 시간이에요. 잘한 것부터 보여 드릴게요."
        content.sound = .default
        var when = DateComponents()
        when.weekday = 1
        when.hour = 20
        try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }
}

/// 알림 본문을 눌러 앱을 열었을 때 보여 줄 물건. 홈이 받아서 상세 화면을 연다.
@MainActor
@Observable
final class NotificationRoute {
    static let shared = NotificationRoute()
    var keyID: UUID?
    /// 통계 탭을 열지(주간 돌아보기 알림).
    var openStats = false
    /// 시작 화면을 건너뛸지. 홈이 keyID를 먼저 비워도 앱이 놓치지 않게 따로 둔다.
    var skipSplash = false
}

/// 알림 버튼 처리와 앱이 열려 있을 때의 알림 표시.
///
/// 완료 핸들러 형태로 구현하고 반드시 메인 스레드에서 부른다. async 형태로 두면 알림을 눌렀을 때 시스템이
/// 백그라운드 스레드에서 UIKit 상태 저장을 실행해 앱이 강제 종료된다(TestFlight 빌드 43 크래시, 2026-11-03).
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let id = (response.notification.request.content.userInfo["keyID"] as? String).flatMap(UUID.init(uuidString:))
        let isRecap = response.notification.request.identifier == WeeklyRecap.id
        DispatchQueue.main.async {
            if isRecap {
                MainActor.assumeIsolated {
                    NotificationRoute.shared.skipSplash = true
                    NotificationRoute.shared.openStats = true
                }
            }
            if let id {
                MainActor.assumeIsolated {
                    switch action {
                    case HabitReminders.recordAction, HabitReminders.attendAction: HabitReminders.recordFromNotification(id)
                    case UNNotificationDefaultActionIdentifier:
                        NotificationRoute.shared.skipSplash = true
                        NotificationRoute.shared.keyID = id
                    default: break
                    }
                }
            }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
    }
}
