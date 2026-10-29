import Foundation

/// Vision feature print 하나. revision이 다르면 거리 비교가 성립하지 않으므로 함께 보관한다.
public struct FeatureVector: Codable, Equatable, Sendable {
    public var values: [Float]
    public var revision: Int

    public init(values: [Float], revision: Int) {
        self.values = values
        self.revision = revision
    }

    /// 유클리드 거리. 차원이나 revision이 다르면 nil (비교 불가).
    public func distance(to other: FeatureVector) -> Float? {
        guard revision == other.revision, values.count == other.values.count, !values.isEmpty else { return nil }
        var sum: Float = 0
        for i in values.indices {
            let d = values[i] - other.values[i]
            sum += d * d
        }
        return sum.squareRoot()
    }
}

/// 등록된 물건 하나의 비교용 정보.
public struct RegisteredKey: Equatable, Sendable {
    public var id: UUID
    public var references: [FeatureVector]
    /// 이 거리보다 멀면 이 물건이 아니라고 본다. 거리는 확률이 아니다.
    public var threshold: Float

    public init(id: UUID, references: [FeatureVector], threshold: Float) {
        self.id = id
        self.references = references
        self.threshold = threshold
    }
}

public struct Candidate: Equatable, Sendable {
    public var keyID: UUID
    public var distance: Float
}

/// 프레임 한 장의 인식 결과. `match`일 때만 동작 실행으로 이어질 수 있다.
public enum ScanOutcome: Equatable, Sendable {
    case match(Candidate)
    /// 후보가 둘 이상 비슷하게 가깝다. 사용자가 직접 골라야 한다.
    case ambiguous([Candidate])
    case noMatch
}

public struct MatcherConfig: Equatable, Sendable {
    /// 1위 거리 / 2위 거리. 이 값보다 크면(두 후보가 비슷하면) 모호하다고 본다.
    public var ambiguityRatio: Float

    public init(ambiguityRatio: Float = 0.85) {
        self.ambiguityRatio = ambiguityRatio
    }
}

public struct ObjectMatcher: Sendable {
    public var config: MatcherConfig

    public init(config: MatcherConfig = MatcherConfig()) {
        self.config = config
    }

    /// 진단용: 물건별 최소 거리를 가까운 순으로. evaluate와 같은 계산이며 임계값은 적용하지 않는다.
    public func distances(_ query: FeatureVector, against keys: [RegisteredKey]) -> [Candidate] {
        keys.compactMap { key in
            key.references.compactMap { query.distance(to: $0) }.min().map { Candidate(keyID: key.id, distance: $0) }
        }
        .sorted { $0.distance < $1.distance }
    }

    public func evaluate(_ query: FeatureVector, against keys: [RegisteredKey]) -> ScanOutcome {
        // 물건별 거리 = 참조 이미지들 중 가장 가까운 것. revision이 맞지 않는 참조는 건너뛴다.
        let ranked = keys.compactMap { key -> (Candidate, Float)? in
            guard let best = key.references.compactMap({ query.distance(to: $0) }).min() else { return nil }
            return (Candidate(keyID: key.id, distance: best), key.threshold)
        }
        .sorted { $0.0.distance < $1.0.distance }

        let withinThreshold = ranked.filter { $0.0.distance <= $0.1 }.map(\.0)
        guard let first = withinThreshold.first else { return .noMatch }

        // 임계값 밖의 물건도 2위로 보고 비교한다. 1위만 겨우 통과한 상황을 걸러내기 위해서다.
        if ranked.count > 1 {
            let second = ranked[1].0
            if second.distance <= 0 || first.distance / second.distance > config.ambiguityRatio {
                let close = ranked.map(\.0).filter { $0.distance <= second.distance }
                return .ambiguous(close)
            }
        }
        return .match(first)
    }
}

/// 연속 프레임에서 같은 결과가 일정 횟수 이상 이어져야 확정한다.
/// 한 프레임짜리 오인식으로 실행되는 일과, 물건을 옮기는 도중 선택 창이 뜨는 일을 함께 막는다.
public struct StabilityFilter: Sendable {
    private enum Tracking: Equatable, Sendable {
        case key(UUID)
        case ambiguous
    }

    public let requiredStreak: Int
    private var tracking: Tracking?
    private var streak = 0

    public init(requiredStreak: Int = 3) {
        self.requiredStreak = max(1, requiredStreak)
    }

    /// 확정된 결과가 있으면 돌려준다. 확정 후 내부 상태는 초기화된다.
    public mutating func feed(_ outcome: ScanOutcome) -> ScanOutcome? {
        let current: Tracking
        switch outcome {
        case .match(let candidate): current = .key(candidate.keyID)
        case .ambiguous: current = .ambiguous
        case .noMatch:
            reset()
            return nil
        }
        if current == tracking {
            streak += 1
        } else {
            tracking = current
            streak = 1
        }
        guard streak >= requiredStreak else { return nil }
        reset()
        return outcome
    }

    public mutating func reset() {
        tracking = nil
        streak = 0
    }
}

public enum Calibration {
    public static let minimumThreshold: Float = 0.45
    public static let maximumThreshold: Float = 0.72
    public static let marginFactor: Float = 1.2

    /// 같은 물건 참조끼리의 최대 거리에 여유를 둔 값을 임계값으로 제안한다.
    ///
    /// 실측(iPhone, Vision feature print 리비전 2, 물체 크롭 적용, 2026-10-29):
    /// 같은 물건의 참조 사진끼리 ≥ 0.56, 다른 물건(키보드↔영양제) 0.78, 무관한 물건 1.01.
    /// 이전 값(상한 0.9, 여유 1.6)은 다른 물건까지 기준 안에 들어와 오실행을 냈다.
    /// 상한 0.72는 0.78 아래, 여유 1.2는 참조 사진 분산이 크면 상한에서 잘리도록 둔 값이다.
    public static func suggestThreshold(for references: [FeatureVector]) -> Float {
        min(max(maxIntraDistance(of: references) * marginFactor, minimumThreshold), maximumThreshold)
    }

    /// 같은 물건 참조끼리의 최대 거리. 등록 화면의 진단 표시에도 쓴다.
    public static func maxIntraDistance(of references: [FeatureVector]) -> Float {
        var maxIntra: Float = 0
        for i in references.indices {
            for j in references.indices where j > i {
                if let d = references[i].distance(to: references[j]) { maxIntra = max(maxIntra, d) }
            }
        }
        return maxIntra
    }
}
