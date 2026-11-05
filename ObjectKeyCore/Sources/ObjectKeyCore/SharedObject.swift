import Foundation

/// 같은 물건을 쓰는 습관 묶기. 예: 운동화 → "5분 걷기", "외출 전 스트레칭".
/// 습관은 자기 사진을 갖거나(source가 nil) 다른 습관(물건 주인)의 사진을 빌려 쓴다. 빌려 쓰기는 한 단계만 둔다.
public enum SharedObject {
    public struct Habit: Equatable, Sendable {
        public var id: UUID
        public var source: UUID?
        public init(id: UUID, source: UUID?) { self.id = id; self.source = source }
    }

    /// 이 습관이 속한 물건의 주인. 빌려 온 주인이 없어졌으면 자기 자신이 주인이다.
    public static func owner(of habit: Habit, among habits: [Habit]) -> UUID {
        guard let source = habit.source, source != habit.id, habits.contains(where: { $0.id == source }) else { return habit.id }
        return source
    }

    /// 물건별 묶음. 순서는 넘겨준 순서(보통 등록순)를 따르고, 묶음 안에서는 주인이 맨 앞이다.
    public static func groups(_ habits: [Habit]) -> [[UUID]] {
        var order: [UUID] = []
        var members: [UUID: [UUID]] = [:]
        for habit in habits {
            let owner = owner(of: habit, among: habits)
            if members[owner] == nil { order.append(owner); members[owner] = [] }
            if habit.id != owner { members[owner]?.append(habit.id) }
        }
        return order.map { [$0] + (members[$0] ?? []) }
    }

    /// 주인 습관을 지울 때 사진을 넘겨받을 습관. 빌려 쓰던 습관 중 가장 먼저 넘겨준 것. 없으면 nil.
    public static func heir(of owner: UUID, among habits: [Habit]) -> UUID? {
        habits.first { $0.id != owner && $0.source == owner }?.id
    }
}
