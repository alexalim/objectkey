import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ObjectKeyCore

/// 앱 저장소 ↔ 백업 파일. 형식과 합치기 규칙은 Core(Backup)에 있고, 여기서는 옮겨 담기만 한다.
@MainActor
enum BackupService {
    static func makeFile(context: ModelContext) throws -> BackupFile {
        let keys = try context.fetch(FetchDescriptor<KeyObject>())
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        let notes = try context.fetch(FetchDescriptor<DayNote>())
        return BackupFile(
            exportedAt: .now,
            keys: keys.map { k in
                BackupFile.Key(id: k.id, name: k.name, emoji: k.emoji, actionKind: k.actionKind, countdownMinutes: k.countdownMinutes,
                               threshold: k.threshold, createdAt: k.createdAt, dailyGoal: k.dailyGoal, cue: k.cue,
                               reminderMinute: k.reminderMinute, scheduleKind: k.scheduleKind, scheduleWeekdays: k.scheduleWeekdays,
                               timesPerWeek: k.timesPerWeek, attendStartMinute: k.attendStartMinute, attendMinutes: k.attendMinutes,
                               tags: k.tags, shots: k.shots.map { BackupFile.Shot(featureData: $0.featureData, revision: $0.revision) },
                               isQuit: k.isQuit, measureStep: k.measureStep, measureUnit: k.measureUnit,
                               healthMetric: k.healthMetric.isEmpty ? nil : k.healthMetric, healthTarget: k.healthTarget,
                               routineSteps: k.routineSteps.isEmpty ? nil : k.routineSteps,
                               photoSourceID: k.photoSourceID)
            },
            logs: logs.map(dto),
            notes: notes.map { BackupFile.Note(keyID: $0.keyID, day: $0.day, text: $0.text) })
    }

    /// 가져온 개수(물건, 기록, 메모).
    static func restore(_ file: BackupFile, context: ModelContext) throws -> (keys: Int, logs: Int, notes: Int) {
        let existingKeys = try context.fetch(FetchDescriptor<KeyObject>())
        let existingLogs = try context.fetch(FetchDescriptor<ActivityLog>())
        let existingNotes = try context.fetch(FetchDescriptor<DayNote>())
        let plan = Backup.plan(importing: file, existingKeyIDs: Set(existingKeys.map(\.id)), existingLogs: existingLogs.map(dto),
                               existingNotes: existingNotes.map { BackupFile.Note(keyID: $0.keyID, day: $0.day, text: $0.text) })
        for k in plan.keys {
            let key = KeyObject(name: k.name, emoji: k.emoji, action: .session, threshold: k.threshold, dailyGoal: k.dailyGoal)
            key.id = k.id
            key.createdAt = k.createdAt
            key.actionKind = k.actionKind
            key.countdownMinutes = k.countdownMinutes
            key.cue = k.cue
            key.reminderMinute = k.reminderMinute
            key.scheduleKind = k.scheduleKind
            key.scheduleWeekdays = k.scheduleWeekdays
            key.timesPerWeek = k.timesPerWeek
            key.attendStartMinute = k.attendStartMinute
            key.attendMinutes = k.attendMinutes
            key.tags = k.tags
            key.isQuit = k.isQuit ?? false
            key.measureStep = k.measureStep ?? 0
            key.measureUnit = k.measureUnit ?? ""
            key.healthMetric = k.healthMetric ?? ""
            key.healthTarget = k.healthTarget ?? 0
            key.routineSteps = k.routineSteps ?? []
            key.photoSourceID = k.photoSourceID
            context.insert(key)
            key.shots = k.shots.map { shot in
                let values = shot.featureData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                return ReferenceShot(vector: FeatureVector(values: values, revision: shot.revision), thumbnail: nil)
            }
        }
        for l in plan.logs {
            context.insert(ActivityLog(keyID: l.keyID, keyName: l.keyName, kind: l.kind, startedAt: l.startedAt,
                                       duration: l.duration, amount: l.amount ?? 1))
        }
        for n in plan.notes { context.insert(DayNote(keyID: n.keyID, day: n.day, text: n.text)) }
        try context.save()
        WidgetBridge.refreshFromStore()
        MokiShortcuts.updateAppShortcutParameters()
        return (plan.keys.count, plan.logs.count, plan.notes.count)
    }

    private static func dto(_ l: ActivityLog) -> BackupFile.Log {
        BackupFile.Log(keyID: l.keyID, keyName: l.keyName, kind: l.kind, startedAt: l.startedAt, duration: l.duration,
                       amount: l.amount == 1 ? nil : l.amount)
    }
}

/// 파일 앱(iCloud Drive 포함)에 저장할 백업 문서.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.unreadable }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
