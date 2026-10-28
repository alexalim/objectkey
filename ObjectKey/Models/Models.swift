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
    @Relationship(deleteRule: .cascade, inverse: \ReferenceShot.key)
    var shots: [ReferenceShot] = []

    init(name: String, emoji: String, action: KeyAction, threshold: Float) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.actionKind = "session"
        self.countdownMinutes = 5
        self.threshold = threshold
        self.createdAt = .now
        self.action = action
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
