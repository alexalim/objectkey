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
    }
}
