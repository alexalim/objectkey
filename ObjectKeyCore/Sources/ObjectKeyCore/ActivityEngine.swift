import Foundation

/// 물건에 부여할 수 있는 능력. v0.1은 앱 자체 기능만 제공한다.
public enum KeyAction: Codable, Equatable, Sendable {
    /// 시간 기록 세션. 스캔하면 시작, 다시 스캔하면 종료.
    case session
    /// 휴식 같은 카운트다운. 진행 중인 세션은 일시정지했다가 끝나면 이어간다.
    case countdown(minutes: Int)
    /// 스캔할 때마다 +1.
    case counter
}

/// 일시정지된 세션. 일시정지 시간은 기록 시간에서 빠진다.
public struct PausedSession: Codable, Equatable, Sendable {
    public var keyID: UUID
    public var startedAt: Date
    public var accumulated: TimeInterval
}

public enum ActivityState: Codable, Equatable, Sendable {
    case idle
    case session(keyID: UUID, startedAt: Date, segmentStart: Date, accumulated: TimeInterval)
    case countdown(keyID: UUID, endsAt: Date, paused: PausedSession?)

    public var activeKeyID: UUID? {
        switch self {
        case .idle: return nil
        case .session(let id, _, _, _): return id
        case .countdown(let id, _, _): return id
        }
    }

    /// 진행 중이거나 휴식 때문에 멈춰 둔 활동에 이 물건이 관여하는지.
    public func involves(_ keyID: UUID) -> Bool {
        if activeKeyID == keyID { return true }
        if case .countdown(_, _, let paused?) = self { return paused.keyID == keyID }
        return false
    }
}

/// 엔진이 앱에 요청하는 부수 효과. 저장·진동·알림은 앱 층이 수행한다.
public enum Effect: Equatable, Sendable {
    case recordSession(keyID: UUID, startedAt: Date, duration: TimeInterval)
    case incrementCounter(keyID: UUID, at: Date)
    case scheduleCountdownEnd(keyID: UUID, at: Date)
    case cancelCountdownEnd
    case feedback(Feedback)
}

public enum Feedback: Equatable, Sendable {
    case started, stopped, counted, countdownFinished
}

/// 실행 전에 사용자 확인이 필요한 전환.
public struct PendingSwitch: Equatable, Sendable {
    public var from: UUID
    public var to: UUID
    public var action: KeyAction
}

public enum ScanResolution: Equatable, Sendable {
    case executed([Effect])
    case needsConfirmation(PendingSwitch)
    case needsChoice([UUID])
    case notRecognized
}

public struct ActivityEngine: Sendable {
    public private(set) var state: ActivityState

    public init(state: ActivityState = .idle) {
        self.state = state
    }

    /// 인식 결과를 처리한다. `.match`가 아니면 상태도 효과도 바뀌지 않는다.
    public mutating func handle(_ outcome: ScanOutcome, actions: [UUID: KeyAction], now: Date) -> ScanResolution {
        switch outcome {
        case .noMatch:
            return .notRecognized
        case .ambiguous(let candidates):
            return .needsChoice(candidates.map(\.keyID))
        case .match(let candidate):
            guard let action = actions[candidate.keyID] else { return .notRecognized }
            return activate(candidate.keyID, action: action, now: now)
        }
    }

    /// 사용자가 직접 고른 물건(수동 선택·모호한 후보 중 선택)을 실행한다.
    public mutating func activate(_ keyID: UUID, action: KeyAction, now: Date) -> ScanResolution {
        // 앱이 백그라운드에 있던 사이 휴식이 끝났을 수 있다. 판단 전에 먼저 반영한다.
        let expired = tick(now: now)
        if case .counter = action {
            return .executed(expired + [.incrementCounter(keyID: keyID, at: now), .feedback(.counted)])
        }
        // 휴식 중에 멈춰 둔 세션의 물건을 다시 비추면 휴식을 끝내고 그 세션을 이어간다. 기록을 둘로 쪼개지 않는다.
        if case .session = action, case .countdown(_, _, let paused?) = state, paused.keyID == keyID {
            state = resumed(paused, now: now)
            return .executed(expired + [.cancelCountdownEnd, .feedback(.started)])
        }
        if let active = state.activeKeyID, active != keyID, requiresConfirmation(switchingTo: action) {
            return .needsConfirmation(PendingSwitch(from: active, to: keyID, action: action))
        }
        return .executed(expired + apply(keyID, action: action, now: now))
    }

    public mutating func confirm(_ pending: PendingSwitch, now: Date) -> [Effect] {
        guard state.activeKeyID == pending.from else { return [] }
        var effects = finishCurrent(now: now)
        effects += apply(pending.to, action: pending.action, now: now)
        return effects
    }

    /// 카운트다운 만료를 확인한다. 앱이 포그라운드로 돌아오거나 타이머가 울릴 때 호출한다.
    public mutating func tick(now: Date) -> [Effect] {
        guard case .countdown(_, let endsAt, let paused) = state, now >= endsAt else { return [] }
        // 늦게 확인해도 세션은 휴식이 끝난 시각부터 이어진 것으로 본다.
        state = resumed(paused, now: endsAt)
        return [.feedback(.countdownFinished)]
    }

    /// 진행 중인 활동을 끝내고 기록한다. 물건 삭제 전에 호출한다.
    public mutating func finish(now: Date) -> [Effect] {
        _ = tick(now: now)
        return finishCurrent(now: now)
    }

    // MARK: - 내부 전이

    /// 세션 중 휴식(카운트다운)으로 가는 건 의도된 흐름이라 확인 없이 진행한다.
    private func requiresConfirmation(switchingTo action: KeyAction) -> Bool {
        if case .countdown = action, case .session = state { return false }
        return true
    }

    private mutating func apply(_ keyID: UUID, action: KeyAction, now: Date) -> [Effect] {
        switch (action, state) {
        case (.session, .session(let id, _, _, _)) where id == keyID:
            return finishCurrent(now: now)
        case (.session, _):
            state = .session(keyID: keyID, startedAt: now, segmentStart: now, accumulated: 0)
            return [.feedback(.started)]
        case (.countdown, .countdown(let id, _, let paused)) where id == keyID:
            state = resumed(paused, now: now)
            return [.cancelCountdownEnd, .feedback(.stopped)]
        case (.countdown(let minutes), .session(let id, let startedAt, let segmentStart, let accumulated)):
            let paused = PausedSession(keyID: id, startedAt: startedAt,
                                       accumulated: accumulated + now.timeIntervalSince(segmentStart))
            return startCountdown(keyID, minutes: minutes, paused: paused, now: now)
        case (.countdown(let minutes), _):
            return startCountdown(keyID, minutes: minutes, paused: nil, now: now)
        case (.counter, _):
            return [.incrementCounter(keyID: keyID, at: now), .feedback(.counted)]
        }
    }

    private mutating func startCountdown(_ keyID: UUID, minutes: Int, paused: PausedSession?, now: Date) -> [Effect] {
        let endsAt = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        state = .countdown(keyID: keyID, endsAt: endsAt, paused: paused)
        return [.scheduleCountdownEnd(keyID: keyID, at: endsAt), .feedback(.started)]
    }

    /// 진행 중인 활동을 끝낸다. 휴식 중이었다면 멈춰 둔 세션까지 기록한다.
    private mutating func finishCurrent(now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch state {
        case .idle:
            return []
        case .session(let id, let startedAt, let segmentStart, let accumulated):
            effects.append(.recordSession(keyID: id, startedAt: startedAt,
                                          duration: accumulated + now.timeIntervalSince(segmentStart)))
        case .countdown(_, _, let paused):
            effects.append(.cancelCountdownEnd)
            if let paused {
                effects.append(.recordSession(keyID: paused.keyID, startedAt: paused.startedAt, duration: paused.accumulated))
            }
        }
        state = .idle
        effects.append(.feedback(.stopped))
        return effects
    }

    private func resumed(_ paused: PausedSession?, now: Date) -> ActivityState {
        guard let paused else { return .idle }
        return .session(keyID: paused.keyID, startedAt: paused.startedAt, segmentStart: now, accumulated: paused.accumulated)
    }
}
