import Foundation

/// 플러스를 쓸 수 있는 상태. 산 것과 맛보기를 나눠야 화면 문구(사용 중 / n일 남음)와 결제 버튼이 맞게 나온다.
public enum PlusAccess: Equatable, Sendable {
    /// 평생 이용권을 샀다.
    case owned
    /// 7일 맛보기 중. 끝나는 때까지 플러스 기능이 열린다.
    case trial(endsAt: Date)
    /// 맛보기를 이미 써서 끝났다. 다시 시작할 수 없다(맛보기 상품은 Apple 계정에 한 번만 남는다).
    case trialUsed
    case none

    public var grantsPlus: Bool {
        switch self {
        case .owned, .trial: true
        case .trialUsed, .none: false
        }
    }
}

/// 7일 맛보기. 0원 비소모성 상품(지침 3.1.1의 "XX-day Trial")을 받은 때부터 센다.
public enum PlusTrial {
    public static let days = 7

    public static func access(owned: Bool, trialStarted: Date?, now: Date) -> PlusAccess {
        if owned { return .owned }
        guard let trialStarted else { return .none }
        let endsAt = trialStarted.addingTimeInterval(TimeInterval(days * 86_400))
        return now < endsAt ? .trial(endsAt: endsAt) : .trialUsed
    }

    /// 남은 날 수(올림). 마지막 날은 "1일 남음"으로 보인다.
    public static func daysLeft(until endsAt: Date, now: Date) -> Int {
        max(0, Int((endsAt.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}
