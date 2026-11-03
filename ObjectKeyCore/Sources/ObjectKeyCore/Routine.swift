import Foundation

/// 단계별 루틴. 시간 기록 물건에 "세수 3분 → 양치 2분"처럼 단계를 붙인다.
/// 지금 단계는 따로 저장하지 않고 흐른 시간으로 계산한다(멈췄다 이어도 그대로 맞는다).
public struct RoutineStep: Equatable, Sendable {
    public var name: String
    public var minutes: Int

    public init(name: String, minutes: Int) {
        self.name = name
        self.minutes = max(1, minutes)
    }

    /// 저장 형식 "세수|3". 읽을 수 없으면 nil.
    public init?(stored: String) {
        let parts = stored.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let m = Int(parts[1]), m > 0 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        self.init(name: name, minutes: m)
    }

    public var stored: String { "\(name)|\(minutes)" }
}

public struct RoutineProgress: Equatable, Sendable {
    /// 0부터. 모든 단계를 지났으면 steps.count.
    public var index: Int
    /// 지금 단계에서 남은 초. 끝났으면 0.
    public var remaining: TimeInterval
    public var isFinished: Bool
}

public enum Routine {
    public static func steps(_ stored: [String]) -> [RoutineStep] { stored.compactMap(RoutineStep.init(stored:)) }

    public static func totalMinutes(_ steps: [RoutineStep]) -> Int { steps.reduce(0) { $0 + $1.minutes } }

    /// 흐른 시간(초)으로 지금 단계를 구한다.
    public static func progress(_ steps: [RoutineStep], elapsed: TimeInterval) -> RoutineProgress {
        var start: TimeInterval = 0
        for (i, step) in steps.enumerated() {
            let end = start + TimeInterval(step.minutes * 60)
            if elapsed < end { return RoutineProgress(index: i, remaining: end - elapsed, isFinished: false) }
            start = end
        }
        return RoutineProgress(index: steps.count, remaining: 0, isFinished: true)
    }

    /// 앞으로 단계가 바뀌는 시각과 그때 시작할 단계(마지막은 "끝"으로 nil). 이미 지난 경계는 뺀다.
    /// - Parameter runStart: 흐른 시간 0에 해당하는 시각(멈춘 시간을 뺀 가상의 시작).
    public static func upcomingBoundaries(_ steps: [RoutineStep], runStart: Date, now: Date) -> [(at: Date, next: RoutineStep?)] {
        var result: [(Date, RoutineStep?)] = []
        var offset: TimeInterval = 0
        for (i, step) in steps.enumerated() {
            offset += TimeInterval(step.minutes * 60)
            let at = runStart.addingTimeInterval(offset)
            if at > now { result.append((at, i + 1 < steps.count ? steps[i + 1] : nil)) }
        }
        return result
    }
}
