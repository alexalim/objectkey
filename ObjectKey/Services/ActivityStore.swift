import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications
import ObjectKeyCore

/// ActivityEngine을 감싸 상태를 보존하고, 엔진이 요청한 효과(기록·진동·알림)를 실행한다.
@MainActor
@Observable
final class ActivityStore {
    private(set) var engine: ActivityEngine
    /// 화면에 잠깐 보여줄 마지막 실행 결과.
    var lastMessage: String?

    private let stateURL: URL
    private static let countdownNotificationID = "objectkey.countdown"

    init() {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appending(path: "activity-state.json")
        let saved = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(ActivityState.self, from: $0) }
        engine = ActivityEngine(state: saved ?? .idle)
    }

    var state: ActivityState { engine.state }

    func handle(_ outcome: ScanOutcome, keys: [KeyObject], context: ModelContext) -> ScanResolution {
        let resolution = engine.handle(outcome, actions: actionMap(keys), now: .now)
        finish(resolution, keys: keys, context: context)
        return resolution
    }

    /// 수동 선택 경로. 카메라 권한이 없거나 모호한 후보 중 골랐을 때 쓴다.
    func activate(_ key: KeyObject, keys: [KeyObject], context: ModelContext) -> ScanResolution {
        let resolution = engine.activate(key.id, action: key.action, now: .now)
        finish(resolution, keys: keys, context: context)
        return resolution
    }

    func confirm(_ pending: PendingSwitch, keys: [KeyObject], context: ModelContext) {
        perform(engine.confirm(pending, now: .now), keys: keys, context: context)
    }

    /// 물건을 지우기 전에, 그 물건이 진행 중이거나 멈춰 둔 활동이면 먼저 끝내고 기록한다.
    func finishIfInvolved(_ key: KeyObject, keys: [KeyObject], context: ModelContext) {
        guard engine.state.involves(key.id) else { return }
        perform(engine.finish(now: .now), keys: keys, context: context)
    }

    func tick(keys: [KeyObject], context: ModelContext) {
        perform(engine.tick(now: .now), keys: keys, context: context)
    }

    // MARK: - 효과 실행

    private func finish(_ resolution: ScanResolution, keys: [KeyObject], context: ModelContext) {
        if case .executed(let effects) = resolution { perform(effects, keys: keys, context: context) }
    }

    private func perform(_ effects: [Effect], keys: [KeyObject], context: ModelContext) {
        guard !effects.isEmpty else { return }
        let names = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0.name) })
        for effect in effects {
            switch effect {
            case .recordSession(let id, let startedAt, let duration):
                context.insert(ActivityLog(keyID: id, keyName: names[id] ?? "삭제된 물건", kind: "session",
                                           startedAt: startedAt, duration: duration))
                lastMessage = "\(names[id] ?? "세션") \(Self.format(duration)) 기록"
            case .incrementCounter(let id, let at):
                context.insert(ActivityLog(keyID: id, keyName: names[id] ?? "삭제된 물건", kind: "counter",
                                           startedAt: at, duration: 0))
                lastMessage = "\(names[id] ?? "카운터") +1"
            case .scheduleCountdownEnd(let id, let at):
                scheduleNotification(name: names[id] ?? "휴식", at: at)
            case .cancelCountdownEnd:
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.countdownNotificationID])
            case .feedback(let feedback):
                play(feedback)
            }
        }
        try? context.save()
        persist()
    }

    private func play(_ feedback: Feedback) {
        switch feedback {
        case .started: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .stopped: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .counted: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .countdownFinished: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func scheduleNotification(name: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) 끝"
            content.body = "멈춰 둔 세션이 있으면 다시 이어집니다."
            content.sound = .default
            let interval = max(1, date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.countdownNotificationID, content: content, trigger: trigger))
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(engine.state) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func actionMap(_ keys: [KeyObject]) -> [UUID: KeyAction] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0.action) })
    }

    /// 데이터 전체 삭제 시 진행 중 상태도 비운다.
    func reset() {
        engine = ActivityEngine()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.countdownNotificationID])
        try? FileManager.default.removeItem(at: stateURL)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h)시간 \(m)분" : (m > 0 ? "\(m)분 \(s)초" : "\(s)초")
    }
}
