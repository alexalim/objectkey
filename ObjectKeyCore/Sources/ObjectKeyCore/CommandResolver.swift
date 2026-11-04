import Foundation

/// 자연어 해석 결과를 앱 값으로 옮기는 규칙. 언어 모델이 낸 값은 믿지 않고 여기서 범위를 다시 확인한다.
public enum CommandResolver {
    /// "21:00", "9:30", "21시", "21시 30분", "9시 반", "오후 9시", "밤 12시" → 자정부터 분. 못 읽으면 nil.
    public static func minuteOfDay(_ text: String?) -> Int? {
        guard var t = text?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        let half = t.contains("반")
        let night = t.contains("밤") || t.contains("새벽")
        var pm = false, am = false
        for (word, isPM) in [("오후", true), ("저녁", true), ("밤", true), ("오전", false), ("아침", false), ("새벽", false)] where t.contains(word) {
            if isPM { pm = true } else { am = true }
            t = t.replacingOccurrences(of: word, with: "")
        }
        let digits = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var hour = digits.first else { return nil }
        let minute = digits.count > 1 ? digits[1] : (half ? 30 : 0)
        if night, hour == 12 { hour = 0 }          // 밤 12시 = 자정
        else if pm, hour < 12 { hour += 12 }
        if am, hour == 12 { hour = 0 }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// "화", "화요일", "tue" → Calendar weekday(1=일 … 7=토). 언어 모델에게 숫자를 받지 않는다.
    /// 모델마다 월요일을 1로 세기도 해서, 숫자를 그대로 믿으면 화요일 수업이 월요일에 등록된다.
    public static func weekdays(_ names: [String]?) -> [Int] {
        let table: [(String, Int)] = [("일", 1), ("월", 2), ("화", 3), ("수", 4), ("목", 5), ("금", 6), ("토", 7),
                                      ("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
        var result: [Int] = []
        for raw in names ?? [] {
            let n = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if n.hasPrefix("평일") { result += [2, 3, 4, 5, 6]; continue }
            if n.hasPrefix("주말") { result += [1, 7]; continue }
            if let day = table.first(where: { n.hasPrefix($0.0) })?.1 { result.append(day) }
        }
        return Array(Set(result)).sorted()
    }

    /// "며칠 전" 기록. 오늘(0)부터 30일 전까지만 받는다. 미래는 오늘로 본다.
    public static func recordDaysAgo(_ value: Int?) -> Int {
        min(max(value ?? 0, 0), 30)
    }

    /// 요일(1=일 … 7=토) 또는 주 N회. 둘 다 없으면 매일.
    public static func schedule(weekdays: [Int]?, timesPerWeek: Int?) -> HabitSchedule {
        let days = Set((weekdays ?? []).filter { (1...7).contains($0) })
        if !days.isEmpty, days.count < 7 { return .weekdays(days) }
        if let n = timesPerWeek, (1...6).contains(n) { return .perWeek(n) }
        return .daily
    }

    /// 알림 시각. 정한 시각이 있으면 그것, "N분 전"이면 시작에서 뺀다. 없으면 -1(끔).
    public static func reminderMinute(start: Int?, reminder: Int?, before: Int?) -> Int {
        if let reminder { return reminder }
        if let start, let before, before > 0 { return ((start - before) % 1440 + 1440) % 1440 }
        return -1
    }

    /// 말한 이름에 가장 가까운 물건. 같은 이름 → 포함 관계 → 글자 두 개씩 겹치는 정도 순으로 본다.
    public static func matchKey(_ spoken: String, among keys: [(id: UUID, name: String)]) -> UUID? {
        let s = normalize(spoken)
        guard !s.isEmpty else { return nil }
        if let exact = keys.first(where: { normalize($0.name) == s }) { return exact.id }
        let containing = keys.filter { let n = normalize($0.name); return n.contains(s) || s.contains(n) }
        if containing.count == 1 { return containing[0].id }
        let scored = keys.map { ($0.id, similarity(s, normalize($0.name))) }.max { $0.1 < $1.1 }
        if let scored, scored.1 >= 0.3 { return scored.0 }
        if let first = containing.first { return first.id }
        return keyMentioned(in: spoken, among: keys)
    }

    /// 문장 속에 물건 이름의 일부가 나오는지. "어제 책 30분 읽었어" → "읽는 책", "하키 다녀왔어" → "아이스하키 수업".
    /// 이름의 낱말이 두 글자 이상 겹치거나, 한 글자 낱말("책", "물")이 문장에 따로 쓰였으면 그 물건이다. 여럿이면 길게 겹친 쪽.
    private static func keyMentioned(in text: String, among keys: [(id: UUID, name: String)]) -> UUID? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        let flat = normalize(text)
        var best: (id: UUID, length: Int)?
        for key in keys {
            for token in key.name.split(separator: " ").map(String.init) {
                let length: Int
                if token.count == 1 {
                    // "책", "책을", "물" 처럼 그 글자로 시작하는 짧은 낱말
                    length = words.contains { $0.hasPrefix(token) && $0.count <= 2 } ? 1 : 0
                } else {
                    let common = longestCommonSubstring(token, flat)
                    length = common >= 2 ? common : 0
                }
                if length > (best?.length ?? 0) { best = (key.id, length) }
            }
        }
        return best?.id
    }

    private static func longestCommonSubstring(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: y.count + 1), best = 0
        for i in 1...x.count {
            var cur = [Int](repeating: 0, count: y.count + 1)
            for j in 1...y.count where x[i - 1] == y[j - 1] {
                cur[j] = prev[j - 1] + 1
                best = max(best, cur[j])
            }
            prev = cur
        }
        return best
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    /// 두 글자씩 묶은 조각의 자카드 유사도. 한국어 띄어쓰기·조사 차이에 덜 민감하다.
    private static func similarity(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> Set<String> {
            let c = Array(s)
            guard c.count > 1 else { return [s] }
            return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
        }
        let x = grams(a), y = grams(b)
        let union = x.union(y).count
        return union == 0 ? 0 : Double(x.intersection(y).count) / Double(union)
    }

    // MARK: - 문장에서 직접 읽기
    // 기기 안 모델은 작아서 칸을 잘못 채울 때가 있다(문장 전체를 이름에 넣거나, "30분 전"을 휴식 30분으로 읽는 등).
    // 요일·시각·길이·알림·날짜처럼 규칙으로 확실히 읽히는 값은 원문에서 직접 읽고, 모델 값보다 우선한다.

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    /// 문장 속 요일. "화요일", "월수금", "평일", "주말". 없으면 빈 배열.
    public static func extractWeekdays(_ text: String) -> [Int] {
        var names: [String] = []
        if text.contains("평일") { names.append("평일") }
        if text.contains("주말") { names.append("주말") }
        // "화요일", "월·수·금요일", "월수금" 처럼 요일 글자가 붙어 나오는 묶음
        for m in matches("([월화수목금토일][·,/ ]?)+요일|([월화수목금토일]){2,}(?=[ ,]|$|에|마다)", in: text) {
            // "요일"의 '일'을 일요일로 세지 않도록 꼬리를 떼고 센다.
            let days = m[0].hasSuffix("요일") ? String(m[0].dropLast(2)) : m[0]
            names += days.compactMap { "월화수목금토일".contains($0) ? String($0) : nil }
        }
        return weekdays(names)
    }

    /// 시작 시각. "밤 9시", "21시 30분", "9시 반", "21:00". 알림을 뜻하는 "N분 전"은 무시한다.
    public static func extractStart(_ text: String) -> Int? {
        // "1시간"의 '1시'는 시각이 아니다.
        let pattern = "((?:오전|오후|아침|저녁|밤|새벽)\\s*)?(\\d{1,2})\\s*(?:시(?!간)\\s*(?:(\\d{1,2})\\s*분|반)?|:(\\d{2}))"
        guard let m = matches(pattern, in: text).first else { return nil }
        return minuteOfDay(m[0])
    }

    /// 한 번의 길이(분). "90분", "1시간 30분", "2시간". "30분 전"(알림)은 빼고 본다.
    public static func extractDuration(_ text: String) -> Int? {
        if let m = matches("(\\d+)\\s*시간(?:\\s*(\\d+)\\s*분)?(?!\\s*전)", in: text).first, let h = Int(m[1]) {
            return h * 60 + (Int(m[2]) ?? 0)
        }
        // "9시 30분"의 30분은 시각이지 길이가 아니다. 위치로 앞말을 확인한다.
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*분(?!\\s*전)") else { return nil }
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let before = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            if before.hasSuffix("시") { continue }
            if let n = Int(ns.substring(with: m.range(at: 1))) { return n }
        }
        return nil
    }

    /// "주 3회", "일주일에 두 번" → 3, 2. 없으면 nil.
    public static func extractTimesPerWeek(_ text: String) -> Int? {
        guard let m = matches("(?:주|일주일에?)\\s*(\\d+|한|두|세|네|다섯|여섯)\\s*(?:번|회)", in: text).first else { return nil }
        let words = ["한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5, "여섯": 6]
        return Int(m[1]) ?? words[m[1]]
    }

    /// "30분 전에 알려줘" → 30.
    public static func extractRemindBefore(_ text: String) -> Int? {
        if let m = matches("(\\d+)\\s*시간\\s*전", in: text).first, let h = Int(m[1]) { return h * 60 }
        return matches("(\\d+)\\s*분\\s*전", in: text).first.flatMap { Int($0[1]) }
    }

    /// "어제" 1, "그저께·그제" 2, "3일 전" 3, "오늘" 0. 말이 없으면 nil.
    public static func extractDaysAgo(_ text: String) -> Int? {
        if text.contains("그저께") || text.contains("그제") { return 2 }
        if text.contains("어제") { return 1 }
        if let m = matches("(\\d+)\\s*일\\s*전", in: text).first, let n = Int(m[1]) { return recordDaysAgo(n) }
        if text.contains("오늘") { return 0 }
        return nil
    }

    /// 기록할 횟수. "2번", "3회", "두 번". 없으면 nil.
    public static func extractCount(_ text: String) -> Int? {
        if let m = matches("(\\d+)\\s*(?:번|회|알|잔|개)", in: text).first { return Int(m[1]) }
        // 붙여 쓴 말("네번")과 띄어 쓴 말("네 번")을 모두 읽는다. 긴 말부터 본다("열번"이 "한번"보다 먼저).
        let numbers: [(String, Int)] = [("열", 10), ("아홉", 9), ("여덟", 8), ("일곱", 7), ("여섯", 6), ("다섯", 5),
                                        ("네", 4), ("세", 3), ("두", 2), ("한", 1)]
        for (word, n) in numbers {
            if matches("(?<![가-힣])\(word)\\s*(?:번|회|잔|알)", in: text).first != nil { return n }
        }
        return nil
    }

    /// 할 일 종류. 휴식은 말에 휴식·낮잠·타이머가 있을 때만. 수업·레슨이거나 시각과 길이가 다 있으면 참석.
    /// - Returns: "session" / "counter" / "attend" / "countdown"
    public static func inferAction(text: String, model: String?, hasStart: Bool, hasDuration: Bool) -> String {
        let has = { (words: [String]) in words.contains { text.contains($0) } }
        if has(["끊기", "끊을", "끊고", "금연", "금주", "안 하기", "안하기", "참기", "줄이기"]) { return "quit" }
        if has(["휴식", "낮잠", "타이머", "쉬는 시간"]) { return "countdown" }
        if has(["수업", "레슨", "강의", "학원", "클래스", "과외", "PT", "모임", "예배", "미사"]) || (hasStart && hasDuration) { return "attend" }
        if has(["먹기", "먹어", "마시", "복용", "번씩", "회씩"]) { return "counter" }
        // "하루 네번", "하루에 3회"처럼 하루 횟수를 말하면 횟수 습관이다.
        if text.contains("하루"), extractCount(text) != nil { return "counter" }
        if let model, model != "countdown" { return model }
        return "session"
    }

    /// 이름만 남긴다. 요일·시각·길이·알림·부탁하는 말을 뺀다. 모델이 문장 전체를 이름에 넣어도 정리된다.
    public static func cleanName(_ text: String) -> String {
        var s = text
        // 순서가 중요하다: "1시간"을 시각 "1시"보다 먼저 지운다.
        let patterns = [
            "\\d+\\s*(?:시간|분)\\s*전(?:에)?",
            "\\d+\\s*시간(?:\\s*\\d+\\s*분)?(?:씩|동안)?",
            "(?:주|일주일에?)\\s*(?:\\d+|한|두|세|네|다섯|여섯)\\s*(?:번|회)(?:씩)?",
            "(?:하루에?\\s*)?(?:\\d+|(?<![가-힣])(?:한|두|세|네|다섯|여섯|일곱|여덟|아홉|열))\\s*(?:잔|번|회|알|개)(?:씩)?",
            "(?:매주|매일|평일|주말|하루에?)",
            "([월화수목금토일][·,/ ]?)+요일(?:마다|에)?",
            "(?<![가-힣])[월화수목금토일]{2,}(?![가-힣])",
            "(?:오전|오후|아침|저녁|밤|새벽)?\\s*\\d{1,2}\\s*시(?:\\s*\\d{1,2}\\s*분|\\s*반)?(?:에|부터|까지)?",
            "\\d{1,2}:\\d{2}",
            "\\d+\\s*분(?:씩|동안|에)?",
            "(?:알려\\s*줘|알림|알려\\s*주세요|등록해?\\s*줘?|추가해?\\s*줘?|만들어\\s*줘|해\\s*줘|할래|하고\\s*싶어|타이머)",
            "[,.!?·]",
        ]
        for p in patterns {
            s = (try? NSRegularExpression(pattern: p))?.stringByReplacingMatches(
                in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ") ?? s
        }
        return s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
