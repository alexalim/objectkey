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
    /// 태그. "운동", "건강" 같은 이름 목록. (v0.4)
    var tags: [String] = []
    /// 끊기 습관. 횟수 물건인데, 기록은 "저지른 날"이고 기록이 없는 날을 지킨 날로 센다. (v0.4)
    var isQuit: Bool = false
    /// 수치 습관. 한 번 기록할 때 더하는 양과 단위(예: 250, "ml"). 0이면 그냥 횟수. (v0.4)
    var measureStep: Int = 0
    var measureUnit: String = ""
    /// 건강 앱 자동 완료. HealthMetric 원시값("steps" 등)과 하루 목표. 빈 문자열이면 쓰지 않음. (v0.4)
    var healthMetric: String = ""
    var healthTarget: Int = 0
    /// 단계별 루틴. "세수|3" 형식의 단계 목록. 시간 기록 물건에만 쓴다. (v0.4)
    var routineSteps: [String] = []
    /// 같은 물건을 쓰는 다른 습관(물건 주인). 그 사진으로 스캔한다. nil이면 자기 사진을 쓴다. (v0.5)
    var photoSourceID: UUID?
    /// 건너뛴 날(그날 0시). 사정이 있어 쉰 날로, 놓친 날로 치지 않는다. (v0.5)
    var skippedDays: [Date] = []
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
    var supportsGoal: Bool { kind != .countdown }

    /// 저장된 문자열의 동작 종류. 모르는 값이면 시간 기록으로 본다.
    var kind: ActionKind { ActionKind(rawValue: actionKind) ?? .session }

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
        // 참석은 다녀오면 그날을 채운 것이다. 끊기는 안 한 날이 채운 날이다. 둘 다 목표량을 두지 않는다.
        guard supportsGoal, kind != .attend, !isQuit, dailyGoal > 0 else { return nil }
        return kind == .counter ? Double(dailyGoal) : Double(dailyGoal * 60)
    }

    var action: KeyAction {
        get {
            switch kind {
            case .countdown: return .countdown(minutes: countdownMinutes)
            case .counter: return .counter
            case .attend: return .attend(startMinute: attendStartMinute, minutes: attendMinutes)
            case .session: return .session
            }
        }
        set {
            actionKind = newValue.kind.rawValue
            switch newValue {
            case .session, .counter: break
            case .countdown(let minutes): countdownMinutes = minutes
            case .attend(let start, let minutes): attendStartMinute = start; attendMinutes = minutes
            }
        }
    }

    /// 수치 습관이면 한 번에 더하는 양, 아니면 1.
    var recordAmount: Double { measureStep > 0 ? Double(measureStep) : 1 }

    /// "+250ml", "+1", "끊기" 처럼 목록에 보이는 동작 이름.
    var actionTitle: String {
        if isQuit { return "끊기 · 했을 때만 기록" }
        if kind == .counter, measureStep > 0 { return "+\(measureStep)\(measureUnit)" }
        return action.label
    }

    /// 횟수 단위. 수치 습관이면 그 단위.
    var countUnit: String { measureStep > 0 ? measureUnit : "회" }

    var registered: RegisteredKey {
        RegisteredKey(id: id, references: shots.map(\.vector), threshold: threshold)
    }

    /// 이 습관이 쓰는 물건의 주인(사진을 가진 습관). 혼자 쓰면 자기 자신.
    func objectOwner(in keys: [KeyObject]) -> KeyObject {
        let id = SharedObject.owner(of: sharedHabit, among: keys.map(\.sharedHabit))
        return keys.first { $0.id == id } ?? self
    }

    /// 같은 물건을 쓰는 습관들. 주인이 맨 앞이다.
    func objectMembers(in keys: [KeyObject]) -> [KeyObject] {
        let owner = objectOwner(in: keys)
        return [owner] + keys.filter { $0.id != owner.id && $0.objectOwner(in: keys).id == owner.id }
    }

    /// 주인 습관을 지우기 전에 사진과 빌려 쓰던 습관들을 다음 습관에 넘긴다. 안 그러면 사진이 같이 지워진다.
    func handOverObject(in keys: [KeyObject]) {
        let habits = keys.map(\.sharedHabit)
        guard let heirID = SharedObject.heir(of: id, among: habits), let heir = keys.first(where: { $0.id == heirID }) else { return }
        let moved = shots
        shots = []
        heir.shots = moved
        heir.threshold = threshold
        heir.photoSourceID = nil
        for key in keys where key.photoSourceID == id && key.id != heirID { key.photoSourceID = heirID }
    }

    var sharedHabit: SharedObject.Habit { .init(id: id, source: photoSourceID) }

    var skipped: Set<Date> { Set(skippedDays) }

    func isSkipped(_ day: Date, calendar: Calendar = .current) -> Bool { skippedDays.contains(calendar.startOfDay(for: day)) }

    /// 그날 건너뛰기를 켜거나 끈다.
    func toggleSkip(_ day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        if let i = skippedDays.firstIndex(of: start) { skippedDays.remove(at: i) } else { skippedDays.append(start) }
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
    /// 횟수 기록 한 번의 양. 수치 습관이면 250 같은 값, 아니면 1. (v0.4, 기존 기록은 1)
    var amount: Double = 1

    init(keyID: UUID, keyName: String, kind: String, startedAt: Date, duration: Double, amount: Double = 1) {
        self.keyID = keyID
        self.keyName = keyName
        self.kind = kind
        self.startedAt = startedAt
        self.duration = duration
        self.amount = amount
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
        case .session: return "시간 재기"
        case .countdown(let minutes): return "\(minutes)분 휴식 타이머"
        case .counter: return "했어요 체크"
        case .attend(let start, let minutes): return "\(Self.clock(start))–\(Self.clock(start + minutes)) 참석"
        }
    }

    /// 자정부터 분 → "21:00". 자정을 넘기면 다음 날 시각으로 돌린다.
    static func clock(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
