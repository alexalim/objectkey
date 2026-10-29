import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \ActivityLog.startedAt, order: .reverse) private var logs: [ActivityLog]
    @State private var confirmWipe = false

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
                    Text("물건을 비춰 세션을 끝내면 여기에 쌓여요.")
                }
            }
        }
        .navigationTitle("기록")
        .toolbar {
            Menu {
                Button("모든 데이터 삭제", role: .destructive) { confirmWipe = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog("등록한 물건, 사진, 기록을 모두 지웁니다. 되돌릴 수 없어요.", isPresented: $confirmWipe, titleVisibility: .visible) {
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

    private func wipe() {
        try? context.delete(model: ActivityLog.self)
        try? context.delete(model: ReferenceShot.self)
        try? context.delete(model: KeyObject.self)
        try? context.save()
        store.reset()
    }
}
