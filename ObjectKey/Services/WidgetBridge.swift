import Foundation
import SwiftData
import WidgetKit
import ObjectKeyCore

/// 앱 → 홈 화면 위젯. 오늘 할 일 요약을 공유 공간에 쓰고 위젯을 새로 그리게 한다.
@MainActor
enum WidgetBridge {
    static func refresh(keys: [KeyObject], logs: [ActivityLog], state: ObjectKeyCore.ActivityState) {
        let now = Date.now
        let items = keys.filter(\.supportsGoal).compactMap { key -> WidgetSnapshot.Item? in
            let progress = KeyProgress.of(key, logs: logs, state: state, now: now)
            guard TodayPlan.isTodo(key, progress) else { return nil }
            return WidgetSnapshot.Item(id: key.id, name: key.name, emoji: key.emoji.hasPrefix("moki-") ? "" : key.emoji,
                                       done: progress.metToday, streak: progress.streak, atRisk: progress.atRisk,
                                       time: key.todoMinute.map(KeyAction.clock), quit: key.isQuit ? true : nil)
        }
        .sorted { ($0.time ?? "99", $0.name) < ($1.time ?? "99", $1.name) }
        let calendar = Calendar.current
        // 이번 주 요일 점: 어느 습관이든 채운 날이면 켠다. 미래 날은 위젯이 알아서 비운다.
        var metDays = Set<Date>()
        for key in keys where key.supportsGoal {
            let entries = KeyProgress.entries(key, logs: logs.filter { $0.keyID == key.id }, state: state, now: now)
            for (day, status) in DailyProgress.days(entries, goal: key.goalAmount, calendar: calendar) where status == .met { metDays.insert(day) }
        }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekDays = (0..<7).map { offset -> Bool in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return metDays.contains(calendar.startOfDay(for: day))
        }
        let remaining = items.filter { !$0.done }.count
        // 토끼 표정: 다 했으면 축하, 끊기기 직전이면 걱정, 아직이면 기다림, 할 일이 없으면 둘러보기.
        let mood = items.isEmpty ? "scan" : remaining == 0 ? "success" : items.contains(where: { $0.atRisk && !$0.done }) ? "question" : "peek"
        let snapshot = WidgetSnapshot(day: calendar.startOfDay(for: now), items: items, plus: PlusStore.shared.isPlus,
                                      weekDays: weekDays, mood: mood)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.push(snapshot)
        TodayActivitySync.update(snapshot, now: now)
    }

    /// 화면 밖(위젯 버튼·단축어·알림)에서 기록한 뒤 부른다.
    static func refreshFromStore() {
        let context = AppModel.container.mainContext
        guard let keys = try? context.fetch(FetchDescriptor<KeyObject>()),
              let logs = try? context.fetch(FetchDescriptor<ActivityLog>()) else { return }
        refresh(keys: keys, logs: logs, state: ActivityStore.shared.state)
        // 밖에서 기록하면 홈 화면이 없을 수 있다. 오늘 이미 한 습관의 알림이 울리지 않게 여기서도 다시 예약한다.
        Task { await HabitReminders.reschedule(keys: keys, logs: logs, state: ActivityStore.shared.state) }
    }

    /// 위젯 체크 버튼. 단축어와 같은 규칙으로 실행한다.
    static func record(_ rawID: String, at tapped: Date = .now) {
        guard let id = UUID(uuidString: rawID) else { return }
        ActivityStore.shared.runFromOutside(id, at: tapped)
    }
}
