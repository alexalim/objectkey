import Foundation

/// 기기 밖에 보관하는 백업 파일. 앱 저장소(SwiftData)와 따로 정의해, 앱 모델이 바뀌어도 파일 형식은 버전으로 관리한다.
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var keys: [Key]
    public var logs: [Log]
    public var notes: [Note]

    public init(exportedAt: Date, keys: [Key], logs: [Log], notes: [Note]) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.keys = keys
        self.logs = logs
        self.notes = notes
    }

    public struct Key: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var emoji: String
        public var actionKind: String
        public var countdownMinutes: Int
        public var threshold: Float
        public var createdAt: Date
        public var dailyGoal: Int
        public var cue: String
        public var reminderMinute: Int
        public var scheduleKind: String
        public var scheduleWeekdays: Int
        public var timesPerWeek: Int
        public var attendStartMinute: Int
        public var attendMinutes: Int
        public var tags: [String]
        /// 스캔으로 알아보는 데 필요한 특징값. 빠지면 복원한 물건을 스캔할 수 없다. 썸네일은 크기 때문에 넣지 않는다.
        public var shots: [Shot]
        /// 끊기·수치 습관(나중에 생긴 칸). 예전 백업에는 없으므로 선택값이다.
        public var isQuit: Bool?
        public var measureStep: Int?
        public var measureUnit: String?
        public var healthMetric: String?
        public var healthTarget: Int?
        public var routineSteps: [String]?
        /// 사진을 빌려 쓰는 물건 주인(같은 물건의 다른 습관). 없으면 자기 사진을 쓴다.
        public var photoSourceID: UUID?
        /// 건너뛴 날(그날 0시).
        public var skippedDays: [Date]?

        public init(id: UUID, name: String, emoji: String, actionKind: String, countdownMinutes: Int, threshold: Float,
                    createdAt: Date, dailyGoal: Int, cue: String, reminderMinute: Int, scheduleKind: String,
                    scheduleWeekdays: Int, timesPerWeek: Int, attendStartMinute: Int, attendMinutes: Int,
                    tags: [String], shots: [Shot], isQuit: Bool? = nil, measureStep: Int? = nil, measureUnit: String? = nil,
                    healthMetric: String? = nil, healthTarget: Int? = nil, routineSteps: [String]? = nil,
                    photoSourceID: UUID? = nil, skippedDays: [Date]? = nil) {
            self.id = id; self.name = name; self.emoji = emoji; self.actionKind = actionKind
            self.countdownMinutes = countdownMinutes; self.threshold = threshold; self.createdAt = createdAt
            self.dailyGoal = dailyGoal; self.cue = cue; self.reminderMinute = reminderMinute
            self.scheduleKind = scheduleKind; self.scheduleWeekdays = scheduleWeekdays; self.timesPerWeek = timesPerWeek
            self.attendStartMinute = attendStartMinute; self.attendMinutes = attendMinutes; self.tags = tags; self.shots = shots
            self.isQuit = isQuit; self.measureStep = measureStep; self.measureUnit = measureUnit
            self.healthMetric = healthMetric; self.healthTarget = healthTarget; self.routineSteps = routineSteps
            self.photoSourceID = photoSourceID
            self.skippedDays = skippedDays
        }
    }

    public struct Shot: Codable, Equatable, Sendable {
        public var featureData: Data
        public var revision: Int
        public init(featureData: Data, revision: Int) { self.featureData = featureData; self.revision = revision }
    }

    public struct Log: Codable, Equatable, Sendable {
        public var keyID: UUID
        public var keyName: String
        public var kind: String
        public var startedAt: Date
        public var duration: Double
        /// 수치 기록의 양(나중에 생긴 칸). 없으면 1.
        public var amount: Double?
        public init(keyID: UUID, keyName: String, kind: String, startedAt: Date, duration: Double, amount: Double? = nil) {
            self.keyID = keyID; self.keyName = keyName; self.kind = kind; self.startedAt = startedAt; self.duration = duration
            self.amount = amount
        }
    }

    public struct Note: Codable, Equatable, Sendable {
        public var keyID: UUID
        public var day: Date
        public var text: String
        public init(keyID: UUID, day: Date, text: String) { self.keyID = keyID; self.day = day; self.text = text }
    }
}

public enum BackupError: Error, Equatable {
    /// 더 새 버전 앱에서 만든 파일.
    case newerVersion(Int)
    case unreadable
}

public enum Backup {
    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 버전을 먼저 읽어, 더 새 형식이면 알아들을 수 없는 칸 때문에 실패하기 전에 이유를 알려 준다.
        struct Header: Decodable { let version: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BackupError.unreadable }
        guard header.version <= BackupFile.currentVersion else { throw BackupError.newerVersion(header.version) }
        guard let file = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        return file
    }

    /// 가져올 것. 이미 있는 것은 빼서, 같은 파일을 두 번 가져와도 겹치지 않는다.
    public struct ImportPlan: Equatable, Sendable {
        public var keys: [BackupFile.Key]
        public var logs: [BackupFile.Log]
        public var notes: [BackupFile.Note]
    }

    /// 물건은 ID로, 기록은 (물건·시각(초)·종류·길이)로, 메모는 (물건·날)로 같은지 본다. 이미 있는 것은 그대로 둔다.
    public static func plan(importing file: BackupFile, existingKeyIDs: Set<UUID>,
                            existingLogs: [BackupFile.Log], existingNotes: [BackupFile.Note]) -> ImportPlan {
        func logKey(_ l: BackupFile.Log) -> String {
            "\(l.keyID)|\(Int(l.startedAt.timeIntervalSince1970.rounded()))|\(l.kind)|\(Int(l.duration.rounded()))"
        }
        func noteKey(_ n: BackupFile.Note) -> String { "\(n.keyID)|\(Int(n.day.timeIntervalSince1970.rounded()))" }
        var seenLogs = Set(existingLogs.map(logKey))
        var seenNotes = Set(existingNotes.map(noteKey))
        var seenKeys = existingKeyIDs
        let keys = file.keys.filter { seenKeys.insert($0.id).inserted }
        let logs = file.logs.filter { seenLogs.insert(logKey($0)).inserted }
        let notes = file.notes.filter { seenNotes.insert(noteKey($0)).inserted }
        return ImportPlan(keys: keys, logs: logs, notes: notes)
    }
}
