import Foundation
import FoundationModels
import ObjectKeyCore

/// 기기 안 언어 모델(Apple Foundation Models)로 한 문장을 해석한다. 기기 밖으로 보내지 않는다.
/// 모델이 낸 값은 그대로 쓰지 않고 CommandResolver에서 범위를 다시 확인한다.
@available(iOS 26.0, *)
@Generable
struct MokiCommand {
    @Guide(description: "요청 종류. register는 새 습관이나 물건 등록, record는 이미 한 일을 기록, question은 기록이나 통계에 대한 질문")
    var kind: Kind

    @Generable
    enum Kind {
        case register, record, question
    }

    @Guide(description: "습관이나 물건의 짧은 이름(2~10자). 요일·시각·길이·알림 같은 말은 빼고 이름만. 예: 아이스하키 수업, 영양제, 읽는 책")
    var name: String?

    @Guide(description: "어울리는 이모지 한 글자")
    var emoji: String?

    @Guide(description: "동작. session은 시작과 끝이 있는 시간 기록, counter는 횟수 세기, attend는 시간이 정해진 수업이나 레슨 참석, countdown은 휴식 타이머")
    var action: Action?

    @Generable
    enum Action {
        case session, counter, attend, countdown
    }

    @Guide(description: "하는 요일 이름 목록. 예: 화요일만이면 [\"화\"], 월수금이면 [\"월\", \"수\", \"금\"], 평일이면 [\"평일\"]. 매일이면 비워 둔다. 숫자로 쓰지 않는다")
    var weekdays: [String]?

    @Guide(description: "요일을 정하지 않고 일주일에 몇 번 하는지")
    var timesPerWeek: Int?

    @Guide(description: "시작 시각을 사용자가 말한 그대로. 예: 밤 9시, 21:00")
    var startTime: String?

    @Guide(description: "한 번에 걸리는 시간이나 기록할 시간(분 단위 숫자)")
    var minutes: Int?

    @Guide(description: "알림 시각을 사용자가 말한 그대로")
    var reminderTime: String?

    @Guide(description: "시작 몇 분 전에 알릴지(분 단위 숫자)")
    var remindBeforeMinutes: Int?

    @Guide(description: "횟수. 하루 목표 횟수이거나 기록할 횟수")
    var count: Int?

    @Guide(description: "이미 하고 있는 행동 뒤에 붙이는 경우 그 행동. 예: 아침 커피 내린")
    var cue: String?

    @Guide(description: "기록할 날이 오늘부터 며칠 전인지. 오늘 0, 어제 1, 그저께 2")
    var daysAgo: Int?
}

@available(iOS 26.0, *)
@MainActor
enum MokiAssistant {
    /// 쓸 수 없으면 이유, 쓸 수 있으면 nil.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "이 기기는 Apple Intelligence를 지원하지 않아 쓸 수 없어요."
            case .appleIntelligenceNotEnabled:
                return "설정 → Apple Intelligence 및 Siri에서 Apple Intelligence를 켜 주세요."
            case .modelNotReady:
                return "기기 안 AI 모델을 준비하는 중이에요. 잠시 뒤 다시 시도해 주세요."
            @unknown default:
                return "지금은 기기 안 AI를 쓸 수 없어요."
            }
        }
    }

    static func interpret(_ text: String, keyNames: [String], today: String) async throws -> MokiCommand {
        let session = LanguageModelSession(instructions: """
        너는 습관 앱 MOKI의 입력 도우미다. 사용자의 한 문장을 정해진 양식으로만 옮긴다.
        오늘은 \(today)이다. 이미 등록된 물건: \(keyNames.isEmpty ? "없음" : keyNames.joined(separator: ", ")).
        등록된 물건 이름이 나오고 이미 한 일을 말하면 record, 새로 시작하거나 만들겠다고 하면 register, 묻는 말이면 question이다.
        사용자가 말하지 않은 값은 채우지 말고 비워 둔다. "N분 전에 알려줘"는 알림이지 휴식 시간이 아니다.
        예) "화요일 밤 9시 아이스하키 수업 90분, 30분 전에 알려줘" → kind register, name 아이스하키 수업, action attend,
           weekdays ["화"], startTime 밤 9시, minutes 90, remindBeforeMinutes 30
        예) "어제 책 30분 읽었어" → kind record, name 책, minutes 30, daysAgo 1
        예) "이번 달 영양제 몇 번 먹었어?" → kind question
        """)
        return try await session.respond(to: text, generating: MokiCommand.self).content
    }

    static func answer(_ question: String, facts: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
        너는 습관 앱 MOKI의 도우미다. 아래 사실만 근거로 한국어로 두세 문장 이내로 답한다.
        숫자는 사실에 있는 것만 쓰고 지어내지 않는다. 사실로 답할 수 없으면 모른다고 말한다.
        """)
        return try await session.respond(to: "사실:\n\(facts)\n\n질문: \(question)").content
    }
}
