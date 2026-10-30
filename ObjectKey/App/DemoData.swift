#if DEBUG
import Foundation
import SwiftData
import ObjectKeyCore

/// UI 테스트용 데모 데이터. `-ui-demo` 인자로 켜면 메모리 저장소에 물건과 기록을 채운다.
/// 실제 저장소와 출시 빌드에는 영향이 없다.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-demo") }

    @MainActor
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: KeyObject.self, ReferenceShot.self, ActivityLog.self, configurations: config)
        seed(container.mainContext)
        return container
    }()

    @MainActor
    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        func day(_ ago: Int, hour: Int = 9) -> Date {
            calendar.date(byAdding: .day, value: -ago, to: calendar.startOfDay(for: .now))!.addingTimeInterval(TimeInterval(hour * 3600))
        }

        let supplement = KeyObject(name: "영양제", emoji: "💊", action: .counter, threshold: 0.6)
        supplement.cue = "아침 식사 한"
        supplement.reminderMinute = 9 * 60
        let book = KeyObject(name: "읽는 책", emoji: "moki-reading", action: .session, threshold: 0.6, dailyGoal: 30)
        book.schedule = .weekdays([2, 4, 6])
        let workout = KeyObject(name: "운동 매트", emoji: "moki-exercise", action: .session, threshold: 0.6)
        workout.schedule = .perWeek(3)
        let nap = KeyObject(name: "낮잠 베개", emoji: "💤", action: .countdown(minutes: 20), threshold: 0.6)
        [supplement, book, workout, nap].forEach { context.insert($0) }

        // 영양제: 하루 빠진 날이 있지만 이어지는 14일, 오늘은 아직.
        for ago in 1...14 where ago != 6 {
            context.insert(ActivityLog(keyID: supplement.id, keyName: supplement.name, kind: "counter", startedAt: day(ago), duration: 0))
        }
        for ago in [1, 3, 5, 8, 10, 12, 15, 17] {
            context.insert(ActivityLog(keyID: book.id, keyName: book.name, kind: "session", startedAt: day(ago, hour: 21),
                                       duration: ago % 3 == 0 ? 900 : 2100))
        }
        for ago in [2, 4, 9, 11, 13] {
            context.insert(ActivityLog(keyID: workout.id, keyName: workout.name, kind: "session", startedAt: day(ago, hour: 7), duration: 1800))
        }
        try? context.save()
    }
}
#endif
