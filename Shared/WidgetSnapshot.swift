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
        /// 끊기 습관. 위젯의 ○ 버튼은 "했다"를 기록하므로 끊기에는 버튼을 두지 않는다. (옛 파일에는 없어 선택값)
        var quit: Bool?
    }

    /// 쓴 날의 0시.
    var day: Date
    var items: [Item]
    /// MOKI 플러스 여부. 위젯·워치는 플러스에서만 열린다. 옛 파일에는 없어 nil이면 열어 둔다.
    var plus: Bool? = nil
    /// 이번 주 7일(달력의 첫 요일부터) 중 어느 날이든 습관을 채웠으면 true. 위젯의 요일 점에 쓴다. 날이 바뀌면 nil로 비운다.
    var weekDays: [Bool]? = nil
    /// 토끼 표정 이름("peek" 등). 앱이 오늘 상황을 보고 정한다.
    var mood: String? = nil

    /// 아직 안 한 것 수(끊기 습관은 "지키는 중"이면 한 것으로 본다).
    var remaining: Int { items.filter { !$0.done }.count }

    /// 위젯·워치를 잠가야 하는지.
    var locked: Bool { plus == false }

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
        // 어제 요약이다. 완료 표시와 요일 점은 믿을 수 없으니 비우고, 표정은 평범하게 둔다.
        return WidgetSnapshot(day: calendar.startOfDay(for: now), items: items.map { var i = $0; i.done = false; return i },
                              plus: plus, weekDays: nil, mood: "peek")
    }

    var doneCount: Int { items.filter(\.done).count }
}

extension WidgetSnapshot {
    /// 위젯 갤러리 미리보기와 워치 화면 점검(-ui-demo)에 쓰는 보기용 요약.
    static let sample = WidgetSnapshot(day: .now, items: [
        .init(id: UUID(), name: "영양제", emoji: "💊", done: true, streak: 13, atRisk: false, time: "09:00"),
        .init(id: UUID(), name: "읽는 책", emoji: "📚", done: false, streak: 4, atRisk: false, time: nil),
        .init(id: UUID(), name: "아이스하키 수업", emoji: "🏒", done: false, streak: 2, atRisk: false, time: "21:00"),
    ], plus: true, weekDays: [true, true, false, true, true, false, false], mood: "peek")
}
