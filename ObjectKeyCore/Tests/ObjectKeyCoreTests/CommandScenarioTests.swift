import XCTest
@testable import ObjectKeyCore

// 계층: Scenario — 사용자가 실제로 쓸 법한 문장을 넣어, 모델 없이 규칙만으로 등록·기록 칸이 맞게 채워지는지 본다.
// 기기 안 모델은 CI에서 돌릴 수 없으므로, 모델보다 우선하는 규칙의 범위를 여기서 넓게 확인한다.
final class CommandScenarioTests: XCTestCase {
    private struct Register {
        let text: String
        var name: String
        var kind: String
        var weekdays: [Int] = []
        var start: Int? = nil
        var duration: Int? = nil
        var before: Int? = nil
        var perWeek: Int? = nil
        var count: Int? = nil
    }

    private let registers: [Register] = [
        .init(text: "화요일 밤 9시 아이스하키 수업 90분, 30분 전에 알려줘", name: "아이스하키 수업", kind: "attend",
              weekdays: [3], start: 1260, duration: 90, before: 30),
        .init(text: "화요일 밤 9시 아이스하키 수업 30분 전에 알려줘", name: "아이스하키 수업", kind: "attend",
              weekdays: [3], start: 1260, before: 30),
        .init(text: "매주 월요일 저녁 7시 반 피아노 레슨 1시간", name: "피아노 레슨", kind: "attend",
              weekdays: [2], start: 1170, duration: 60),
        .init(text: "토요일 오전 10시 수영 강습 50분, 1시간 전에 알려줘", name: "수영 강습", kind: "attend",
              weekdays: [7], start: 600, duration: 50, before: 60),
        .init(text: "평일 아침 7시 30분에 달리기 30분", name: "달리기", kind: "attend",
              weekdays: [2, 3, 4, 5, 6], start: 450, duration: 30),
        .init(text: "월수금 저녁 8시 헬스", name: "헬스", kind: "session", weekdays: [2, 4, 6], start: 1200),
        .init(text: "주 3회 헬스 1시간", name: "헬스", kind: "session", duration: 60, perWeek: 3),
        .init(text: "일주일에 두 번 요가", name: "요가", kind: "session", perWeek: 2),
        .init(text: "하루에 물 8잔 마시기", name: "물 마시기", kind: "counter", count: 8),
        .init(text: "매일 아침 영양제 먹기", name: "아침 영양제 먹기", kind: "counter"),
        .init(text: "점심 먹고 20분 낮잠", name: "점심 먹고 낮잠", kind: "countdown", duration: 20),
        .init(text: "자기 전에 일기 쓰기 10분", name: "자기 전에 일기 쓰기", kind: "session", duration: 10),
        .init(text: "책 읽기", name: "책 읽기", kind: "session"),
        .init(text: "주말 오후 2시 반 테니스 레슨 2시간", name: "테니스 레슨", kind: "attend",
              weekdays: [1, 7], start: 870, duration: 120),
        .init(text: "목요일마다 영어 학원 밤 8시부터 1시간 30분", name: "영어 학원", kind: "attend",
              weekdays: [5], start: 1200, duration: 90),
        // TestFlight: "하루 네번"(붙여 씀)을 못 읽어 목표 없는 시간 기록으로 등록됐다.
        .init(text: "횡격막 호흡 명상 하루 네번", name: "횡격막 호흡 명상", kind: "counter", count: 4),
        .init(text: "스트레칭 하루 세 번", name: "스트레칭", kind: "counter", count: 3),
        .init(text: "담배 끊기", name: "담배 끊기", kind: "quit"),
        .init(text: "야식 안 하기", name: "야식 안 하기", kind: "quit"),
        .init(text: "커피 휴식 15분 타이머 등록해줘", name: "커피 휴식", kind: "countdown", duration: 15),
    ]

    func test_registerSentences() {
        var failures: [String] = []
        for r in registers {
            let start = CommandResolver.extractStart(r.text)
            let duration = CommandResolver.extractDuration(r.text)
            let got = (
                name: CommandResolver.cleanName(r.text),
                kind: CommandResolver.inferAction(text: r.text, model: nil, hasStart: start != nil, hasDuration: duration != nil),
                weekdays: CommandResolver.extractWeekdays(r.text),
                start: start, duration: duration,
                before: CommandResolver.extractRemindBefore(r.text),
                perWeek: CommandResolver.extractTimesPerWeek(r.text),
                count: CommandResolver.extractCount(r.text)
            )
            var diff: [String] = []
            if got.name != r.name { diff.append("이름 \(got.name)≠\(r.name)") }
            if got.kind != r.kind { diff.append("종류 \(got.kind)≠\(r.kind)") }
            if got.weekdays != r.weekdays { diff.append("요일 \(got.weekdays)≠\(r.weekdays)") }
            if got.start != r.start { diff.append("시작 \(String(describing: got.start))≠\(String(describing: r.start))") }
            if got.duration != r.duration { diff.append("길이 \(String(describing: got.duration))≠\(String(describing: r.duration))") }
            if got.before != r.before { diff.append("알림 \(String(describing: got.before))≠\(String(describing: r.before))") }
            if got.perWeek != r.perWeek { diff.append("주N \(String(describing: got.perWeek))≠\(String(describing: r.perWeek))") }
            if r.count != nil, got.count != r.count { diff.append("횟수 \(String(describing: got.count))≠\(String(describing: r.count))") }
            if !diff.isEmpty { failures.append("「\(r.text)」 " + diff.joined(separator: ", ")) }
        }
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    private struct Record {
        let text: String
        var daysAgo: Int?
        var duration: Int? = nil
        var count: Int? = nil
        var key: String
    }

    private let keyNames = ["읽는 책", "사무실 영양제", "아이스하키 수업", "물", "피아노 레슨", "헬스"]

    private let records: [Record] = [
        .init(text: "어제 책 30분 읽었어", daysAgo: 1, duration: 30, key: "읽는 책"),
        .init(text: "그제 피아노 1시간 쳤어", daysAgo: 2, duration: 60, key: "피아노 레슨"),
        .init(text: "오늘 영양제 먹었어", daysAgo: 0, key: "사무실 영양제"),
        .init(text: "영양제 2알 먹음", daysAgo: nil, count: 2, key: "사무실 영양제"),
        .init(text: "어제 물 세 번 마셨어", daysAgo: 1, count: 3, key: "물"),
        .init(text: "3일 전에 하키 다녀왔어", daysAgo: 3, key: "아이스하키 수업"),
        .init(text: "방금 헬스 45분 했어", daysAgo: nil, duration: 45, key: "헬스"),
        // "독서"↔"책" 같은 뜻 연결은 규칙으로 하지 않는다(모델 몫). 규칙은 이름 글자가 나오는 경우만.
        .init(text: "그저께 책 20분", daysAgo: 2, duration: 20, key: "읽는 책"),
    ]

    func test_recordSentences() {
        let keys = keyNames.map { (id: UUID(), name: $0) }
        var failures: [String] = []
        for r in records {
            var diff: [String] = []
            let days = CommandResolver.extractDaysAgo(r.text)
            if days != r.daysAgo { diff.append("날짜 \(String(describing: days))≠\(String(describing: r.daysAgo))") }
            if r.duration != nil, CommandResolver.extractDuration(r.text) != r.duration {
                diff.append("길이 \(String(describing: CommandResolver.extractDuration(r.text)))≠\(String(describing: r.duration))")
            }
            if r.count != nil, CommandResolver.extractCount(r.text) != r.count {
                diff.append("횟수 \(String(describing: CommandResolver.extractCount(r.text)))≠\(String(describing: r.count))")
            }
            let matched = CommandResolver.matchKey(r.text, among: keys).flatMap { id in keys.first { $0.id == id }?.name }
            if matched != r.key { diff.append("물건 \(matched ?? "없음")≠\(r.key)") }
            if !diff.isEmpty { failures.append("「\(r.text)」 " + diff.joined(separator: ", ")) }
        }
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }
}
