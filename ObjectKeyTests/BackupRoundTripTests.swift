import SwiftData
import XCTest
import ObjectKeyCore
@testable import MOKI

// 계층: Integration — 실제 SwiftData 저장소 → 백업 파일(JSON) → 다른 저장소로 복원.
// Core의 BackupTests는 합치기 규칙만 본다. 여기서는 앱 모델의 필드가 빠짐없이 옮겨지는지 본다.
@MainActor
final class BackupRoundTripTests: XCTestCase {
    func testRestoreKeepsEveryKeyFieldLogAndNote() throws {
        let source = ModelContext(try AppTestStore.make())
        let water = KeyObject(name: "물", emoji: "💧", action: .counter, threshold: 0.55, dailyGoal: 2000)
        water.measureStep = 250
        water.measureUnit = "ml"
        water.tags = ["건강"]
        water.schedule = .weekdays([2, 4, 6])
        water.reminderMinute = 9 * 60
        water.cue = "커피 내린"
        water.healthMetric = "steps"
        water.healthTarget = 8000
        let smoke = KeyObject(name: "담배", emoji: "🚬", action: .counter, threshold: 0.6)
        smoke.isQuit = true
        let morning = KeyObject(name: "아침 루틴", emoji: "🌅", action: .session, threshold: 0.6)
        morning.routineSteps = ["세수|3", "스트레칭|5"]
        let hockey = KeyObject(name: "아이스하키", emoji: "🏒", action: .attend(startMinute: 21 * 60, minutes: 90), threshold: 0.6)
        [water, smoke, morning, hockey].forEach(source.insert)
        water.shots = [ReferenceShot(vector: FeatureVector(values: [0.1, 0.2, 0.3], revision: 2), thumbnail: nil)]
        source.insert(ActivityLog(keyID: water.id, keyName: water.name, kind: "counter", startedAt: .now, duration: 0, amount: 250))
        source.insert(DayNote(keyID: water.id, day: Calendar.current.startOfDay(for: .now), text: "더웠음"))
        try source.save()

        let data = try Backup.encode(try BackupService.makeFile(context: source))
        let target = ModelContext(try AppTestStore.make())
        let counts = try BackupService.restore(try Backup.decode(data), context: target)
        XCTAssertEqual(counts.keys, 4)
        XCTAssertEqual(counts.logs, 1)
        XCTAssertEqual(counts.notes, 1)

        let restored = try target.fetch(FetchDescriptor<KeyObject>())
        let w = try XCTUnwrap(restored.first { $0.id == water.id })
        XCTAssertEqual(w.kind, .counter)
        XCTAssertEqual(w.measureStep, 250)
        XCTAssertEqual(w.measureUnit, "ml")
        XCTAssertEqual(w.dailyGoal, 2000)
        XCTAssertEqual(w.tags, ["건강"])
        XCTAssertEqual(w.schedule, .weekdays([2, 4, 6]))
        XCTAssertEqual(w.reminderMinute, 9 * 60)
        XCTAssertEqual(w.cue, "커피 내린")
        XCTAssertEqual(w.healthMetric, "steps")
        XCTAssertEqual(w.healthTarget, 8000)
        XCTAssertEqual(w.threshold, 0.55)
        XCTAssertEqual(w.shots.first?.vector.values, [0.1, 0.2, 0.3])
        XCTAssertEqual(w.shots.first?.vector.revision, 2)
        XCTAssertEqual(restored.first { $0.id == smoke.id }?.isQuit, true)
        XCTAssertEqual(restored.first { $0.id == morning.id }?.routineSteps, ["세수|3", "스트레칭|5"])
        XCTAssertEqual(restored.first { $0.id == hockey.id }?.action, .attend(startMinute: 21 * 60, minutes: 90))
        XCTAssertEqual(try target.fetch(FetchDescriptor<ActivityLog>()).first?.amount, 250)
        XCTAssertEqual(try target.fetch(FetchDescriptor<DayNote>()).first?.text, "더웠음")
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        let source = ModelContext(try AppTestStore.make())
        let book = KeyObject(name: "책", emoji: "📚", action: .session, threshold: 0.6)
        source.insert(book)
        source.insert(ActivityLog(keyID: book.id, keyName: book.name, kind: "session", startedAt: .now, duration: 600))
        try source.save()
        let file = try BackupService.makeFile(context: source)

        let target = ModelContext(try AppTestStore.make())
        _ = try BackupService.restore(file, context: target)
        let again = try BackupService.restore(file, context: target)
        XCTAssertEqual(again.keys, 0)
        XCTAssertEqual(again.logs, 0)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<KeyObject>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<ActivityLog>()), 1)
    }
}
