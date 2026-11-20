import AppIntents
import SwiftData
import ObjectKeyCore

/// 단축어·Siri·액션 버튼에서 고를 수 있는 등록 물건.
struct KeyEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "MOKI 물건"
    static let defaultQuery = KeyEntityQuery()

    let id: UUID
    let name: String
    let emoji: String

    var displayRepresentation: DisplayRepresentation {
        // 캐릭터 에셋 이름("moki-…")은 글자로 보여 줄 수 없어 이름만 쓴다.
        DisplayRepresentation(title: "\(emoji.hasPrefix("moki-") ? name : "\(emoji) \(name)")")
    }

    init(_ key: KeyObject) {
        id = key.id
        name = key.name
        emoji = key.emoji
    }
}

struct KeyEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [KeyEntity] {
        try allKeys().filter { identifiers.contains($0.id) }.map(KeyEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [KeyEntity] {
        try allKeys().map(KeyEntity.init)
    }

    @MainActor
    private func allKeys() throws -> [KeyObject] {
        try AppModel.container.mainContext.fetch(FetchDescriptor<KeyObject>(sortBy: [SortDescriptor(\.createdAt)]))
    }
}

/// 카메라 없이 물건의 동작을 실행한다. 목록에서 "지금 기록"을 누른 것과 같다.
struct RecordKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "MOKI 물건 기록"
    static let description = IntentDescription("등록한 습관을 카메라 없이 기록해요(했어요 체크, 시간 재기, 참석, 휴식).")

    @Parameter(title: "물건")
    var key: KeyEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$key) 기록")
    }

    init() {}

    init(key: KeyEntity) {
        self.key = key
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ActivityStore.shared
        guard let run = store.runFromOutside(key.id) else {
            return .result(dialog: "물건을 찾을 수 없어요. 앱에서 지워졌을 수 있어요.")
        }
        let switched = run.finishedPrevious.map { "하던 \($0) 기록을 끝내고 저장했어요. " } ?? ""
        return .result(dialog: "\(switched)\(Self.outcome(run.key, store: store))")
    }

    /// 실행 뒤 상태로 무슨 일이 있었는지 말한다. 시작은 기록이 남지 않아 store 메시지가 없거나 이전 활동의 것이다.
    @MainActor
    private static func outcome(_ key: KeyObject, store: ActivityStore) -> String {
        switch store.state {
        case .session(let id, _, _, _) where id == key.id: return "\(key.name) 시간 기록을 시작했어요."
        case .countdown(let id, _, _) where id == key.id: return "\(key.name) 휴식을 시작했어요."
        default: return store.lastMessage ?? "\(key.name) 기록했어요."
        }
    }
}

/// 단축어에서 묻는 오늘 현황. 위젯 요약은 늦을 수 있어 저장소에서 바로 계산한다.
@MainActor
private enum IntentFacts {
    static func load() -> (keys: [KeyObject], logs: [ActivityLog])? {
        let context = AppModel.container.mainContext
        guard let keys = try? context.fetch(FetchDescriptor<KeyObject>(sortBy: [SortDescriptor(\.createdAt)])),
              let logs = try? context.fetch(FetchDescriptor<ActivityLog>()) else { return nil }
        return (keys, logs)
    }

    static func progress(_ id: UUID) -> (key: KeyObject, progress: KeyProgress)? {
        guard let facts = load(), let key = facts.keys.first(where: { $0.id == id }) else { return nil }
        return (key, KeyProgress.of(key, logs: facts.logs, state: ActivityStore.shared.state))
    }
}

/// 오늘 아직 안 한 습관 수. 자동화의 조건("0보다 크면 알림")이나 다른 앱에 넘길 값으로 쓴다.
struct TodayRemainingIntent: AppIntent {
    static let title: LocalizedStringResource = "MOKI 오늘 남은 습관"
    static let description = IntentDescription("오늘 아직 안 한 습관 수를 알려 줘요. 이름은 말로 읽어 줘요.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let facts = IntentFacts.load() else { return .result(value: 0, dialog: "기록을 읽지 못했어요.") }
        let state = ActivityStore.shared.state
        let left = facts.keys.filter(\.supportsGoal).filter { key in
            let progress = KeyProgress.of(key, logs: facts.logs, state: state)
            return TodayPlan.isTodo(key, progress) && !progress.metToday
        }
        if left.isEmpty { return .result(value: 0, dialog: "오늘 할 습관을 다 했어요!") }
        let names = left.map(\.name).joined(separator: ", ")
        return .result(value: left.count, dialog: "오늘 \(left.count)개 남았어요. \(names)")
    }
}

/// 습관 하나의 연속 일수.
struct HabitStreakIntent: AppIntent {
    static let title: LocalizedStringResource = "MOKI 연속 일수"
    static let description = IntentDescription("습관을 며칠째 이어 가고 있는지 알려 줘요.")

    @Parameter(title: "물건")
    var key: KeyEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$key) 연속 일수")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let found = IntentFacts.progress(key.id) else { return .result(value: 0, dialog: "물건을 찾을 수 없어요.") }
        let streak = found.progress.streak
        return .result(value: streak, dialog: streak > 0 ? "\(found.key.name) \(streak)일째 이어 가고 있어요." : "\(found.key.name), 오늘부터 다시 시작이에요.")
    }
}

/// 오늘 했는지. 자동화에서 "안 했으면 알림" 같은 조건에 쓴다.
struct HabitDoneTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "MOKI 오늘 했는지"
    static let description = IntentDescription("습관을 오늘 채웠는지 참/거짓으로 알려 줘요.")

    @Parameter(title: "물건")
    var key: KeyEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$key) 오늘 했는지")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        guard let found = IntentFacts.progress(key.id) else { return .result(value: false, dialog: "물건을 찾을 수 없어요.") }
        let done = found.progress.metToday
        return .result(value: done, dialog: done ? "\(found.key.name), 오늘 했어요." : "\(found.key.name), 아직 안 했어요.")
    }
}

struct MokiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordKeyIntent(),
            phrases: [
                "\(.applicationName)에서 \(\.$key) 기록",
                "\(.applicationName) \(\.$key) 기록해 줘",
                "\(.applicationName)로 기록",
            ],
            shortTitle: "물건 기록",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TodayRemainingIntent(),
            phrases: [
                "\(.applicationName) 오늘 남은 습관",
                "\(.applicationName)에서 오늘 뭐 남았어",
            ],
            shortTitle: "오늘 남은 습관",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: HabitStreakIntent(),
            phrases: [
                "\(.applicationName) \(\.$key) 연속 며칠",
                "\(.applicationName)에서 \(\.$key) 며칠째야",
            ],
            shortTitle: "연속 일수",
            systemImageName: "flame"
        )
    }
}
