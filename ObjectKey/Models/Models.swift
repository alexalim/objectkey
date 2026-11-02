import Foundation
import SwiftData
import ObjectKeyCore

/// 능력을 부여받은 물건.
@Model
final class KeyObject {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var actionKind: String
    var countdownMinutes: Int
    var threshold: Float
    var createdAt: Date
    /// 하루 목표. 세션은 분, 카운터는 횟수. 0이면 목표 없음. (v0.2에 추가, 기본값으로 가벼운 마이그레이션)
    var dailyGoal: Int = 0
    /// 습관 쌓기 신호. "커피 내린" 처럼 이미 하고 있는 행동을 적어 두면 "…다음에"로 보여준다. (v0.3)
    var cue: String = ""
    /// 습관 알림 시각. 자정부터 분, -1이면 끔. (v0.4)
    var reminderMinute: Int = -1
    /// 습관 일정. "daily" / "weekdays" / "perWeek". (v0.4)
    var scheduleKind: String = "daily"
    /// 요일 지정일 때 정한 요일. 비트 (weekday - 1), 일요일이 0번 비트.
    var scheduleWeekdays: Int = 0
    /// 주 N회일 때 N.
    var timesPerWeek: Int = 3
    /// 정해진 시간 참석: 시작 시각(자정부터 분)과 길이(분). (v0.4)
    var attendStartMinute: Int = 21 * 60
    var attendMinutes: Int = 90
    @Relationship(deleteRule: .cascade, inverse: \ReferenceShot.key)
    var shots: [ReferenceShot] = []

    init(name: String, emoji: String, action: KeyAction, threshold: Float, dailyGoal: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.actionKind = "session"
        self.countdownMinutes = 5
        self.threshold = threshold
        self.createdAt = .now
        self.dailyGoal = dailyGoal
        self.action = action
    }

    /// 휴식 타이머는 기록이 남지 않으므로 목표·연속 일수를 두지 않는다.
    var supportsGoal: Bool { actionKind != "countdown" }

    var schedule: HabitSchedule {
        get {
            switch scheduleKind {
            case "weekdays": return .weekdays(Set((1...7).filter { scheduleWeekdays & (1 << ($0 - 1)) != 0 }))
            case "perWeek": return .perWeek(timesPerWeek)
            default: return .daily
            }
        }
        set {
            switch newValue {
            case .daily: scheduleKind = "daily"
            case .weekdays(let days): scheduleKind = "weekdays"; scheduleWeekdays = days.reduce(0) { $0 | (1 << ($1 - 1)) }
            case .perWeek(let n): scheduleKind = "perWeek"; timesPerWeek = n
            }
        }
    }

    /// Progress 계산에 넘길 목표량. 세션은 초, 카운터는 횟수.
    var goalAmount: Double? {
        // 참석은 다녀오면 그날을 채운 것이다. 분 단위 목표를 따로 두지 않는다.
        guard supportsGoal, actionKind != "attend", dailyGoal > 0 else { return nil }
        return actionKind == "counter" ? Double(dailyGoal) : Double(dailyGoal * 60)
    }

    var action: KeyAction {
        get {
            switch actionKind {
            case "countdown": return .countdown(minutes: countdownMinutes)
            case "counter": return .counter
            case "attend": return .attend(startMinute: attendStartMinute, minutes: attendMinutes)
            default: return .session
            }
        }
        set {
            switch newValue {
            case .session: actionKind = "session"
            case .countdown(let minutes): actionKind = "countdown"; countdownMinutes = minutes
            case .counter: actionKind = "counter"
            case .attend(let start, let minutes): actionKind = "attend"; attendStartMinute = start; attendMinutes = minutes
            }
        }
    }

    var registered: RegisteredKey {
        RegisteredKey(id: id, references: shots.map(\.vector), threshold: threshold)
    }
}

/// 물건 등록 시 찍은 참조 이미지 한 장의 특징값.
@Model
final class ReferenceShot {
    var featureData: Data
    var revision: Int
    @Attribute(.externalStorage) var thumbnail: Data?
    var key: KeyObject?

    init(vector: FeatureVector, thumbnail: Data?) {
        self.featureData = vector.values.withUnsafeBufferPointer { Data(buffer: $0) }
        self.revision = vector.revision
        self.thumbnail = thumbnail
    }

    var vector: FeatureVector {
        let values = featureData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return FeatureVector(values: values, revision: revision)
    }
}

/// 세션 종료·카운터 기록. 물건을 지워도 기록은 남도록 이름을 복사해 둔다.
@Model
final class ActivityLog {
    var keyID: UUID
    var keyName: String
    var kind: String
    var startedAt: Date
    var duration: Double

    init(keyID: UUID, keyName: String, kind: String, startedAt: Date, duration: Double) {
        self.keyID = keyID
        self.keyName = keyName
        self.kind = kind
        self.startedAt = startedAt
        self.duration = duration
    }
}

/// 물건별 하루 메모. "출장이라 못 함"처럼 달력 날짜에 붙인다. (v0.4)
@Model
final class DayNote {
    var keyID: UUID
    /// 그날 0시.
    var day: Date
    var text: String

    init(keyID: UUID, day: Date, text: String) {
        self.keyID = keyID
        self.day = day
        self.text = text
    }
}

/// 앱과 단축어가 같이 쓰는 저장소. 단축어는 앱 화면 없이도 실행되므로 한곳에서 만든다.
enum AppModel {
    static let types: [any PersistentModel.Type] = [KeyObject.self, ReferenceShot.self, ActivityLog.self, DayNote.self]

    @MainActor
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(types))
        } catch {
            fatalError("저장소를 열 수 없습니다: \(error)")
        }
    }()
}

extension KeyAction {
    var label: String {
        switch self {
        case .session: return "시간 기록 시작·종료"
        case .countdown(let minutes): return "\(minutes)분 휴식 타이머"
        case .counter: return "횟수 +1"
        case .attend(let start, let minutes): return "\(Self.clock(start))–\(Self.clock(start + minutes)) 참석"
        }
    }

    /// 자정부터 분 → "21:00". 자정을 넘기면 다음 날 시각으로 돌린다.
    static func clock(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
