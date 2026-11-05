import SwiftData
import SwiftUI
import ObjectKeyCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityLog.startedAt, order: .reverse) private var logs: [ActivityLog]

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
                    context.saveOrReport()
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
}
