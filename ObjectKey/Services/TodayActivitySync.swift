import ActivityKit
import Foundation

/// 잠금 화면·Dynamic Island의 "오늘 남은 습관" 현황. 앱을 열었을 때 남은 습관이 있으면 띄우고,
/// 기록이 바뀔 때마다 맞추며, 다 하면 잠깐 축하한 뒤 내리고, 자정이 지나면 내린다.
/// 시작(request)은 iOS 규칙상 앱이 앞에 있을 때만 되므로, 뒤에서 실행될 때는 이미 떠 있는 것만 갱신한다.
@MainActor
enum TodayActivitySync {
    static func update(_ snapshot: WidgetSnapshot, now: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let calendar = Calendar.current
        let dayEnd = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        // 플러스가 아니거나 오늘 할 일이 없으면 띄우지 않는다.
        guard snapshot.plus != false, !snapshot.items.isEmpty else {
            Task { for a in Activity<TodayActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let next = snapshot.items.first { !$0.done && $0.quit != true }
        let atRisk = snapshot.items.first { $0.atRisk && !$0.done }
        let state = TodayActivityAttributes.ContentState(
            remaining: snapshot.remaining, total: snapshot.items.count,
            nextID: next?.id.uuidString, nextName: next?.name ?? "", nextEmoji: next?.emoji ?? "",
            atRiskName: atRisk?.name, dayEnd: dayEnd, mood: snapshot.mood ?? "peek")
        Task {
            // 목록은 실행 시점에 다시 읽는다. 앱이 열릴 때 refresh가 연달아 불려도 카드가 겹쳐 생기지 않게.
            let running = Activity<TodayActivityAttributes>.activities
            // 어제 것, 시스템이 끝낸 것(8시간 뒤), 축하 뒤 대기 중인 것은 정리한다. 살아 있는 것만 갱신 대상이다.
            let alive = running.filter { $0.activityState == .active && $0.content.state.dayEnd > now }
            for a in running where !alive.contains(where: { $0.id == a.id }) { await a.end(nil, dismissalPolicy: .immediate) }
            if state.remaining == 0 {
                // 다 했다: 떠 있던 것만 축하 상태로 바꾸고 30분 뒤 내린다. 새로 띄우지는 않는다.
                for a in alive { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(now.addingTimeInterval(30 * 60))) }
                return
            }
            if let current = alive.first {
                if current.content.state != state { await current.update(ActivityContent(state: state, staleDate: dayEnd)) }
                for extra in alive.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else {
                _ = try? Activity.request(attributes: TodayActivityAttributes(), content: ActivityContent(state: state, staleDate: dayEnd))
            }
        }
    }

    static func endAll() {
        Task { for a in Activity<TodayActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
