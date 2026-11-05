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
            guard key.schedule.isDue(on: now, metToday: progress.metToday, weekDone: progress.weekDone, calendar: .current) else { return nil }
            return WidgetSnapshot.Item(id: key.id, name: key.name, emoji: key.emoji.hasPrefix("moki-") ? "" : key.emoji,
                                       done: progress.metToday, streak: progress.streak, atRisk: progress.atRisk,
                                       time: key.todoMinute.map(KeyAction.clock), quit: key.isQuit ? true : nil)
        }
        .sorted { ($0.time ?? "99", $0.name) < ($1.time ?? "99", $1.name) }
        let snapshot = WidgetSnapshot(day: Calendar.current.startOfDay(for: now), items: items)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.push(snapshot)
    }

    /// 화면 밖(위젯 버튼·단축어·알림)에서 기록한 뒤 부른다.
    static func refreshFromStore() {
        let context = AppModel.container.mainContext
        guard let keys = try? context.fetch(FetchDescriptor<KeyObject>()),
              let logs = try? context.fetch(FetchDescriptor<ActivityLog>()) else { return }
        refresh(keys: keys, logs: logs, state: ActivityStore.shared.state)
    }

    /// 위젯 체크 버튼. 단축어와 같은 규칙으로 실행한다.
    static func record(_ rawID: String) {
        guard let id = UUID(uuidString: rawID) else { return }
        ActivityStore.shared.runFromOutside(id)
    }
}
