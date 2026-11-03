import Foundation

/// 건강 앱 자동 완료 규칙. 하루 값이 목표를 넘은 날마다 기록을 하나씩 남긴다.
public enum HealthMetric: String, CaseIterable, Sendable {
    case steps, exerciseMinutes, mindfulMinutes

    public var label: String {
        switch self {
        case .steps: return "걸음 수"
        case .exerciseMinutes: return "운동 시간"
        case .mindfulMinutes: return "마음챙김"
        }
    }

    public var unit: String {
        switch self {
        case .steps: return "걸음"
        case .exerciseMinutes, .mindfulMinutes: return "분"
        }
    }

    /// 처음 고를 때 제안하는 목표와 한 번에 늘리고 줄이는 폭.
    public var defaultTarget: Int {
        switch self {
        case .steps: return 6000
        case .exerciseMinutes: return 30
        case .mindfulMinutes: return 10
        }
    }

    public var targetStep: Int { self == .steps ? 500 : 5 }
}

public enum HealthRules {
    /// 최근 며칠까지 거슬러 채울지. 앱을 며칠 안 열어도 그동안 걸은 날이 빠지지 않게 한다.
    public static let backfillDays = 7

    /// 목표를 넘었지만 아직 기록이 없는 날(0시). 같은 날은 한 번만 남긴다(여러 번 열어도 겹치지 않게).
    public static func daysToRecord(values: [Date: Double], target: Int, alreadyRecorded: Set<Date>, calendar: Calendar) -> [Date] {
        guard target > 0 else { return [] }
        let recorded = Set(alreadyRecorded.map { calendar.startOfDay(for: $0) })
        return values
            .filter { $0.value >= Double(target) }
            .map { calendar.startOfDay(for: $0.key) }
            .filter { !recorded.contains($0) }
            .sorted()
    }
}
