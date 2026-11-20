import Foundation

/// 건강 앱에 남길 종류. 시간 재기 습관에서 고른다. 운동은 건강 앱의 운동 종류로 나눈다.
public enum HealthWriteTarget: String, CaseIterable, Sendable {
    case mindful, walking, running, cycling, strength, yoga, other

    public var label: String {
        switch self {
        case .mindful: return "마음챙김"
        case .walking: return "운동 · 걷기"
        case .running: return "운동 · 달리기"
        case .cycling: return "운동 · 자전거"
        case .strength: return "운동 · 근력"
        case .yoga: return "운동 · 요가"
        case .other: return "운동 · 기타"
        }
    }

    public var isWorkout: Bool { self != .mindful }
}

/// 건강 앱에 쓸 한 건. 시작과 끝이 있는 기록만 쓴다.
public struct HealthWriteSample: Equatable, Sendable {
    public let target: HealthWriteTarget
    public let start: Date
    public let end: Date
    /// 같은 기록을 두 번 써도(백업 복원 등) 건강 앱이 하나로 합치고, 기록을 지울 때 찾는 열쇠.
    public let syncID: String
}

public enum HealthWrite {
    /// 1분보다 짧은 시간 기록은 잘못 누른 것일 가능성이 커서 남기지 않는다.
    public static let minimumSeconds: Double = 60

    /// 기록 하나를 건강 앱에 쓸지, 쓴다면 무엇을 쓸지.
    /// - 건강 앱에서 읽어 와 자동 완료하는 습관은 쓰지 않는다. 쓰면 자기 기록을 다시 읽어 스스로 채우게 된다.
    /// - 시간 재기 기록만 쓴다. 횟수 기록과 건강 앱에서 온 기록(kind "health")은 시작·끝이 없다.
    public static func sample(keyID: UUID, writeTarget: String, readMetric: String,
                              logKind: String, start: Date, duration: Double) -> HealthWriteSample? {
        guard let target = HealthWriteTarget(rawValue: writeTarget), readMetric.isEmpty,
              logKind == "session", duration >= minimumSeconds else { return nil }
        return HealthWriteSample(target: target, start: start, end: start.addingTimeInterval(duration),
                                 syncID: syncID(keyID: keyID, start: start))
    }

    /// 물건과 시작 시각으로 만든 열쇠. 기록에는 따로 ID가 없지만 같은 물건이 같은 순간에 두 번 시작하지는 않는다.
    public static func syncID(keyID: UUID, start: Date) -> String {
        "moki.\(keyID.uuidString).\(Int(start.timeIntervalSince1970))"
    }
}
