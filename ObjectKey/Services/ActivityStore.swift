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
    /// 앱 화면과 단축어가 같은 진행 상태를 보도록 하나만 둔다.
    static let shared = ActivityStore()

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
        let attendIDs = Set(keys.filter { $0.kind == .attend }.map(\.id))
        let amounts = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0.recordAmount) })
        let units = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0.measureStep > 0 ? "+\($0.measureStep)\($0.measureUnit)" : "+1") })
        for effect in effects {
            switch effect {
            case .recordSession(let id, let startedAt, let duration):
                // 참석은 하루 한 번. 두 번 비추거나 알림 버튼을 또 눌러도 겹쳐 기록하지 않는다.
                if attendIDs.contains(id), Self.hasRecord(id, on: startedAt, context: context) {
                    lastMessage = "\(names[id] ?? "참석") 오늘은 이미 기록했어요"
                    continue
                }
                context.insert(ActivityLog(keyID: id, keyName: names[id] ?? "삭제된 물건", kind: "session",
                                           startedAt: startedAt, duration: duration))
                lastMessage = "\(names[id] ?? "세션") \(Self.format(duration)) 기록"
            case .incrementCounter(let id, let at):
                context.insert(ActivityLog(keyID: id, keyName: names[id] ?? "삭제된 물건", kind: "counter",
                                           startedAt: at, duration: 0, amount: amounts[id] ?? 1))
                lastMessage = "\(names[id] ?? "카운터") \(units[id] ?? "+1")"
            case .scheduleCountdownEnd(let id, let at):
                scheduleNotification(name: names[id] ?? "휴식", at: at)
            case .cancelCountdownEnd:
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.countdownNotificationID])
            case .feedback(let feedback):
                play(feedback)
            }
        }
        context.saveOrReport()
        persist()
        syncLiveActivity(keys: keys)
    }

    // MARK: - 화면 밖에서 실행

    struct OutsideRun {
        let key: KeyObject
        /// 확인 없이 끝내고 기록한 이전 활동 이름.
        let finishedPrevious: String?
    }

    /// 위젯 버튼·워치·단축어·알림 버튼이 모두 이 길로 실행한다. 완료를 누른 것으로 보고 바로 기록한다.
    /// 시간 기록은 화면 밖에서 타이머를 켜면 보이지 않은 채 몇 시간씩 돌 수 있어, 실행 화면의 [완료했어요]처럼
    /// 목표 시간(없으면 10분)만큼 남긴다. 이미 그 물건 타이머가 돌고 있으면 끝내고 기록한다.
    /// - Parameter tapped: 누른 때. 워치에서 쌓였다가 늦게 도착한 기록도 누른 날로 남긴다.
    @discardableResult
    func runFromOutside(_ id: UUID, at tapped: Date = .now) -> OutsideRun? {
        let context = AppModel.container.mainContext
        guard let keys = try? context.fetch(FetchDescriptor<KeyObject>()),
              let key = keys.first(where: { $0.id == id }) else { return nil }
        lastMessage = nil
        var previous: String?
        let runningThis: Bool = if case .session(let running, _, _, _) = engine.state { running == key.id } else { false }
        let recordsNow = key.kind == .counter || key.kind == .attend || (key.kind == .session && !runningThis)
        if recordsNow {
            let minutes = key.kind == .attend ? key.attendMinutes : (key.dailyGoal > 0 ? key.dailyGoal : 10)
            lastMessage = addRecord(key, on: tapped, minutes: minutes, context: context) ?? "\(key.name) 기록했어요."
        } else if case .needsConfirmation(let pending) = activate(key, keys: keys, context: context) {
            // 휴식 타이머, 또는 돌고 있던 그 물건 타이머 끝내기.
            previous = keys.first { $0.id == pending.from }?.name ?? "다른"
            confirm(pending, keys: keys, context: context)
        }
        WidgetBridge.refreshFromStore()
        return OutsideRun(key: key, finishedPrevious: previous)
    }

    // MARK: - 날을 정해 직접 기록

    /// 상세 화면의 "기록 추가"와 한 문장으로 적기가 같이 쓴다. 오늘이면 지금, 지난 날이면 그날 정오로 남긴다.
    /// 횟수 물건은 count번(한 번에 recordAmount씩), 시간 물건은 minutes분. 참석은 하루 한 번만.
    /// - Returns: 기록하지 않은 이유. 기록했으면 nil.
    func addRecord(_ key: KeyObject, on day: Date, count: Int = 1, minutes: Int, context: ModelContext) -> String? {
        let calendar = Calendar.current
        let at = calendar.isDateInToday(day)
            ? Date.now : calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
        switch key.kind {
        case .countdown:
            return "휴식 타이머는 기록이 남지 않아요."
        case .attend where Self.hasRecord(key.id, on: day, context: context):
            return "\(key.name): 그날은 이미 참석으로 기록돼 있어요."
        case .counter:
            for _ in 0..<max(count, 1) {
                context.insert(ActivityLog(keyID: key.id, keyName: key.name, kind: "counter",
                                           startedAt: at, duration: 0, amount: key.recordAmount))
            }
        case .session, .attend:
            context.insert(ActivityLog(keyID: key.id, keyName: key.name, kind: "session",
                                       startedAt: at, duration: Double(minutes * 60)))
        }
        guard context.saveOrReport() else { return "저장하지 못했어요." }
        WidgetBridge.refreshFromStore()
        return nil
    }

    /// 잠금 화면 실시간 현황을 지금 상태에 맞춘다. 앱으로 돌아올 때도 부른다(밖에서 끝났을 수 있다).
    func syncLiveActivity(keys: [KeyObject]) {
        LiveActivitySync.update(engine.state, keys: Dictionary(uniqueKeysWithValues: keys.map { ($0.id, ($0.name, $0.emoji)) }))
        RoutineAlerts.sync(engine.state, keys: keys)
    }

    private static func hasRecord(_ id: UUID, on day: Date, context: ModelContext) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { $0.keyID == id && $0.startedAt >= start && $0.startedAt < end })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
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
            content.body = "멈춰 둔 시간 기록이 있으면 다시 이어져요."
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
        LiveActivitySync.endAll()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.countdownNotificationID])
        try? FileManager.default.removeItem(at: stateURL)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h)시간 \(m)분" : (m > 0 ? "\(m)분 \(s)초" : "\(s)초")
    }
}
