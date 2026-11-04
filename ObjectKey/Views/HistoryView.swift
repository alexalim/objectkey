import SwiftData
import SwiftUI
import ObjectKeyCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \ActivityLog.startedAt, order: .reverse) private var logs: [ActivityLog]
    @State private var confirmWipe = false
    @State private var exportDoc: BackupDocument?
    @State private var importing = false
    @State private var backupMessage: String?

    var body: some View {
        List {
            if !logs.isEmpty {
                Section("물건별 합계") {
                    ForEach(summary) { row in
                        LabeledContent(row.name, value: row.value)
                    }
                }
            }
            Section("최근 기록") {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.keyName).font(.headline)
                        Text("\(log.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(log.kind == "counter" ? "+1" : ActivityStore.format(log.duration))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(logs[i]) }
                    try? context.save()
                }
            }
        }
        .overlay {
            if logs.isEmpty {
                ContentUnavailableView {
                    Image(.reading).resizable().scaledToFit().frame(height: 120)
                    Text("기록이 없어요")
                } description: {
                    Text("기록하면 여기에 쌓여요.")
                }
            }
        }
        .navigationTitle("기록")
        .toolbar {
            Menu {
                NavigationLink { CalibrationView() } label: { Label("인식 점검", systemImage: "viewfinder") }
                Button("백업 내보내기", systemImage: "square.and.arrow.up") { exportBackup() }
                Button("백업 가져오기", systemImage: "square.and.arrow.down") { importing = true }
                Divider()
                Button("모든 데이터 삭제", role: .destructive) { confirmWipe = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("더 보기")
        }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                      document: exportDoc, contentType: .json,
                      defaultFilename: "MOKI 백업 \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { backupMessage = "백업을 저장했어요. iCloud Drive에 두면 기기를 바꿔도 가져올 수 있어요." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            importBackup(from: url)
        }
        .alert("백업", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
        .confirmationDialog("등록한 물건, 사진, 기록을 모두 지워요. 되돌릴 수 없어요.", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("모두 삭제", role: .destructive, action: wipe)
        }
    }

    private struct SummaryRow: Identifiable {
        let name: String
        let value: String
        var id: String { name }
    }

    private var summary: [SummaryRow] {
        Dictionary(grouping: logs, by: \.keyName)
            .map { name, items in
                let sessions = items.filter { $0.kind == "session" }
                let counts = items.count - sessions.count
                var parts: [String] = []
                if !sessions.isEmpty { parts.append(ActivityStore.format(sessions.reduce(0) { $0 + $1.duration })) }
                if counts > 0 { parts.append("\(counts)회") }
                return SummaryRow(name: name, value: parts.joined(separator: " · "))
            }
            .sorted { $0.name < $1.name }
    }

    private func exportBackup() {
        do {
            exportDoc = BackupDocument(data: try Backup.encode(try BackupService.makeFile(context: context)))
        } catch {
            backupMessage = "백업 파일을 만들지 못했어요."
        }
    }

    private func importBackup(from url: URL) {
        // 파일 앱에서 고른 파일은 접근 권한을 잠깐 받아야 읽을 수 있다.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try Backup.decode(try Data(contentsOf: url))
            let added = try BackupService.restore(file, context: context)
            backupMessage = added.keys + added.logs + added.notes == 0
                ? "이미 모두 들어 있어요. 새로 가져온 건 없어요."
                : "물건 \(added.keys)개, 기록 \(added.logs)회, 메모 \(added.notes)개를 가져왔어요."
        } catch BackupError.newerVersion(_) {
            backupMessage = "더 새 버전의 MOKI에서 만든 백업이에요. 앱을 업데이트한 뒤 가져와 주세요."
        } catch {
            backupMessage = "백업 파일을 읽지 못했어요. MOKI에서 내보낸 파일인지 확인해 주세요."
        }
    }

    private func wipe() {
        try? context.delete(model: ActivityLog.self)
        try? context.delete(model: DayNote.self)
        try? context.delete(model: ReferenceShot.self)
        try? context.delete(model: KeyObject.self)
        try? context.save()
        store.reset()
    }
}
