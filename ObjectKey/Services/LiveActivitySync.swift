import ActivityKit
import Foundation
import ObjectKeyCore

/// 엔진 상태를 잠금 화면 실시간 현황과 맞춘다. 활동은 늘 하나만 둔다.
@MainActor
enum LiveActivitySync {
    static func update(_ state: ObjectKeyCore.ActivityState, keys: [UUID: (name: String, emoji: String)]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content: MokiActivityAttributes.ContentState?
        switch state {
        case .idle:
            content = nil
        case .session(let id, _, let segmentStart, let accumulated):
            content = .init(title: keys[id]?.name ?? "기록", emoji: displayEmoji(keys[id]?.emoji), isBreak: false,
                            start: segmentStart.addingTimeInterval(-accumulated), end: nil)
        case .countdown(let id, let endsAt, _):
            // 남은 시간은 end만으로 센다. start는 범위의 아래 끝일 뿐이라 고정값을 줘서 매번 바뀌지 않게 한다.
            content = .init(title: keys[id]?.name ?? "휴식", emoji: displayEmoji(keys[id]?.emoji), isBreak: true,
                            start: endsAt.addingTimeInterval(-12 * 3600), end: endsAt)
        }
        Task {
            let running = Activity<MokiActivityAttributes>.activities
            guard let content else {
                for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            if let current = running.first {
                // 같은 내용이면 건드리지 않는다. 매초 tick마다 갱신하면 시스템이 제한한다.
                if current.content.state.title == content.title, current.content.state.isBreak == content.isBreak,
                   current.content.state.end == content.end, abs(current.content.state.start.timeIntervalSince(content.start)) < 2 { return }
                await current.update(ActivityContent(state: content, staleDate: content.end))
                for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else {
                _ = try? Activity.request(attributes: MokiActivityAttributes(),
                                          content: ActivityContent(state: content, staleDate: content.end))
            }
        }
    }

    static func endAll() {
        Task { for activity in Activity<MokiActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
    }

    private static func displayEmoji(_ emoji: String?) -> String {
        guard let emoji, !emoji.hasPrefix("moki-") else { return "" }
        return emoji
    }
}
