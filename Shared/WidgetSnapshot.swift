import Foundation

/// 홈 화면 위젯이 읽는 오늘 할 일 요약. 앱이 기록이 바뀔 때마다 공유 공간(App Group)에 써 둔다.
/// 위젯은 앱 저장소를 직접 열지 않는다. 저장소를 옮기지 않아도 되고, 위젯이 앱 데이터를 망가뜨릴 일도 없다.
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        /// 이모지. 캐릭터 에셋은 위젯에서 그릴 수 없어 빈 문자열.
        var emoji: String
        var done: Bool
        var streak: Int
        var atRisk: Bool
        /// "21:00" 같은 시각. 없으면 nil.
        var time: String?
    }

    /// 쓴 날의 0시.
    var day: Date
    var items: [Item]

    static let groupID = "group.com.aspynlim.moki"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appending(path: "widget-today.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 앱을 열지 않은 채 날이 바뀌었으면 완료 표시를 지운다. 연속 일수는 앱이 다시 계산할 때까지 그대로 둔다.
    func current(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        guard !calendar.isDate(day, inSameDayAs: now) else { return self }
        return WidgetSnapshot(day: calendar.startOfDay(for: now), items: items.map { var i = $0; i.done = false; return i })
    }

    var doneCount: Int { items.filter(\.done).count }
}
