import ActivityKit
import Foundation

/// 잠금 화면·Dynamic Island에 띄우는 진행 중 활동. 앱과 위젯 확장이 함께 쓴다.
/// 공유 저장소 없이 앱이 상태를 직접 넘겨주므로 App Group이 필요 없다.
struct MokiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 물건 이름.
        var title: String
        /// 이모지. 캐릭터 에셋("moki-…")은 확장에서 그릴 수 없어 빈 문자열로 넘긴다.
        var emoji: String
        /// 휴식(카운트다운)이면 true, 시간 기록이면 false.
        var isBreak: Bool
        /// 시간 기록은 경과를 세기 시작한 시각(누적분만큼 앞당긴 값), 휴식은 시작 시각.
        var start: Date
        /// 휴식이 끝나는 시각. 시간 기록이면 nil.
        var end: Date?
    }
}
