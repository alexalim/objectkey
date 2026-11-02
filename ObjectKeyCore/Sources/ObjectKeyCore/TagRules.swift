import Foundation

/// 습관 태그 규칙. 태그는 물건마다 이름 목록으로만 저장하고, 전체 목록은 쓰는 태그에서 만든다.
public enum TagRules {
    /// 처음부터 고를 수 있게 보여 주는 태그.
    public static let defaults = ["운동", "건강", "공부"]
    public static let maxLength = 10

    /// 입력을 태그 이름으로. 앞뒤 공백과 '#'을 떼고 길이를 자른다. 비면 nil.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return String(s.prefix(maxLength))
    }

    /// 고를 수 있는 태그 목록. 기본 태그를 먼저, 그다음 쓰고 있는 태그를 가나다순으로. 중복 없음.
    public static func all(used: [[String]], includeDefaults: Bool = true) -> [String] {
        let usedSet = Set(used.flatMap { $0 })
        let base = includeDefaults ? defaults : defaults.filter(usedSet.contains)
        let extra = usedSet.subtracting(base).sorted()
        return base + extra
    }

    /// 물건의 태그에서 하나를 바꾼다. 바꾼 이름이 이미 있으면 합친다.
    public static func rename(_ tags: [String], from old: String, to new: String) -> [String] {
        guard let new = normalize(new) else { return tags }
        var result: [String] = []
        for tag in tags {
            let t = tag == old ? new : tag
            if !result.contains(t) { result.append(t) }
        }
        return result
    }

    /// 문장 속 태그. "건강 태그로", "#운동", "운동 태그에" 처럼 태그라고 밝힌 것만 읽는다(이름과 헷갈리지 않게).
    public static func mentioned(in text: String, known: [String]) -> [String] {
        known.filter { tag in
            text.contains("#\(tag)") || text.contains("\(tag) 태그") || text.contains("\(tag)태그")
        }
    }
}
