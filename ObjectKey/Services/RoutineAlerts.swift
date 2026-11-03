import Foundation
import UserNotifications
import ObjectKeyCore

/// 단계별 루틴의 단계가 바뀔 때 알린다. 진행 상태에서 다시 계산하므로, 휴식으로 멈췄다 이어도 시각이 맞는다.
@MainActor
enum RoutineAlerts {
    private static let prefix = "objectkey.routine."

    static func sync(_ state: ObjectKeyCore.ActivityState, keys: [KeyObject]) {
        let center = UNUserNotificationCenter.current()
        Task {
            let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard case .session(let id, _, let segmentStart, let accumulated) = state,
                  let key = keys.first(where: { $0.id == id }) else { return }
            let steps = Routine.steps(key.routineSteps)
            guard !steps.isEmpty,
                  (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let runStart = segmentStart.addingTimeInterval(-accumulated)
            for (i, boundary) in Routine.upcomingBoundaries(steps, runStart: runStart, now: .now).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = key.name
                content.body = boundary.next.map { "다음 단계: \($0.name) \($0.minutes)분" } ?? "루틴 끝! 다시 스캔하면 기록돼요."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, boundary.at.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(i)", content: content, trigger: trigger))
            }
        }
    }
}
