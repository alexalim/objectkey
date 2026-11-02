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
        guard let scored, scored.1 >= 0.3 else { return containing.first?.id }
        return scored.0
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
}
