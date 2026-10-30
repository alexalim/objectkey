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

    /// Progress 계산에 넘길 목표량. 세션은 초, 카운터는 횟수.
    var goalAmount: Double? {
        guard supportsGoal, dailyGoal > 0 else { return nil }
        return actionKind == "counter" ? Double(dailyGoal) : Double(dailyGoal * 60)
    }

    var action: KeyAction {
        get {
            switch actionKind {
            case "countdown": return .countdown(minutes: countdownMinutes)
            case "counter": return .counter
            default: return .session
            }
        }
        set {
            switch newValue {
            case .session: actionKind = "session"
            case .countdown(let minutes): actionKind = "countdown"; countdownMinutes = minutes
            case .counter: actionKind = "counter"
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

extension KeyAction {
    var label: String {
        switch self {
        case .session: return "시간 기록 시작·종료"
        case .countdown(let minutes): return "\(minutes)분 휴식 타이머"
        case .counter: return "횟수 +1"
        }
    }
}
