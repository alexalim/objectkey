import Foundation

/// 스티커 모으기. 가장 길게 이어 간 날 수가 기준에 닿을 때마다 스티커를 하나씩 받는다.
/// 기록에서 다시 계산할 수 있어 따로 저장하지 않는다(백업·복원에도 그대로 따라온다).
public enum Milestones {
    /// 스티커를 받는 연속 일수. 7일(다음 날도 할 확률이 크게 오르는 지점)과 66일(습관 형성 평균)을 넣었다.
    public static let streakDays = [1, 3, 7, 14, 21, 30, 45, 66, 100, 150, 200, 365]

    /// 받은 스티커 수.
    public static func unlocked(bestStreak: Int) -> Int {
        streakDays.filter { bestStreak >= $0 }.count
    }

    /// 다음 스티커까지 남은 날. 다 모았으면 nil.
    public static func daysToNext(bestStreak: Int) -> Int? {
        streakDays.first { $0 > bestStreak }.map { $0 - bestStreak }
    }
}
