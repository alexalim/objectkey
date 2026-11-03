import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 백업 파일 왕복과 가져오기 합치기 규칙. 같은 파일을 두 번 가져와도 겹치지 않아야 한다.
final class BackupTests: XCTestCase {
    private let pill = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_793_286_000)

    private func sample() -> BackupFile {
        let key = BackupFile.Key(id: pill, name: "영양제", emoji: "💊", actionKind: "counter", countdownMinutes: 5, threshold: 0.6,
                                 createdAt: t0, dailyGoal: 2, cue: "아침 식사 한", reminderMinute: 540, scheduleKind: "weekdays",
                                 scheduleWeekdays: 0b0101010, timesPerWeek: 3, attendStartMinute: 1260, attendMinutes: 90,
                                 tags: ["건강"], shots: [BackupFile.Shot(featureData: Data([1, 2, 3, 4]), revision: 2)])
        return BackupFile(exportedAt: t0, keys: [key],
                          logs: [BackupFile.Log(keyID: pill, keyName: "영양제", kind: "counter", startedAt: t0, duration: 0),
                                 BackupFile.Log(keyID: pill, keyName: "영양제", kind: "counter", startedAt: t0.addingTimeInterval(60), duration: 0)],
                          notes: [BackupFile.Note(keyID: pill, day: t0, text: "출장")])
    }

    func test_roundTrip_keepsEverything() throws {
        let file = sample()
        XCTAssertEqual(try Backup.decode(try Backup.encode(file)), file)
    }

    func test_oldFileWithoutNewFields_stillDecodes() throws {
        // 끊기·수치 칸이 생기기 전 형식(칸 없음)도 읽혀야 한다.
        var json = String(data: try Backup.encode(sample()), encoding: .utf8)!
        json = json.replacingOccurrences(of: ",\"isQuit\":null", with: "")
        let file = try Backup.decode(Data(json.utf8))
        XCTAssertNil(file.keys[0].isQuit)
        XCTAssertNil(file.logs[0].amount)
    }

    func test_newFields_roundTrip() throws {
        var file = sample()
        file.keys[0].isQuit = true
        file.keys[0].measureStep = 250
        file.keys[0].measureUnit = "ml"
        file.logs[0].amount = 250
        XCTAssertEqual(try Backup.decode(try Backup.encode(file)), file)
    }

    func test_newerVersion_isRejectedWithReason() throws {
        var file = sample()
        file.version = BackupFile.currentVersion + 1
        XCTAssertThrowsError(try Backup.decode(try Backup.encode(file))) { error in
            XCTAssertEqual(error as? BackupError, .newerVersion(BackupFile.currentVersion + 1))
        }
        XCTAssertThrowsError(try Backup.decode(Data("not json".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
    }

    func test_plan_intoEmpty_takesAll_andSecondImportAddsNothing() {
        let file = sample()
        let first = Backup.plan(importing: file, existingKeyIDs: [], existingLogs: [], existingNotes: [])
        XCTAssertEqual(first.keys.count, 1)
        XCTAssertEqual(first.logs.count, 2)
        XCTAssertEqual(first.notes.count, 1)
        let second = Backup.plan(importing: file, existingKeyIDs: [pill], existingLogs: file.logs, existingNotes: file.notes)
        XCTAssertEqual(second, Backup.ImportPlan(keys: [], logs: [], notes: []))
    }

    func test_plan_keepsNewLogsForExistingKey() {
        let file = sample()
        let partial = Backup.plan(importing: file, existingKeyIDs: [pill], existingLogs: [file.logs[0]], existingNotes: [])
        XCTAssertEqual(partial.keys, [])
        XCTAssertEqual(partial.logs, [file.logs[1]])
        XCTAssertEqual(partial.notes, file.notes)
    }
}
