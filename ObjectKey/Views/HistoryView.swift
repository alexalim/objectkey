import SwiftData
import SwiftUI
import ObjectKeyCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityLog.startedAt, order: .reverse) private var logs: [ActivityLog]
    @Query private var keys: [KeyObject]

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
                        Text("\(log.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(what(log))")
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

    /// 기록 한 줄의 양. 수치 습관은 단위로(+250ml), 건강 앱 자동 완료는 그렇게 적는다.
    private func what(_ log: ActivityLog) -> String {
        switch log.kind {
        case "counter":
            let unit = unit(for: log.keyID)
            return unit.isEmpty ? "+1" : "+\(Int(log.amount))\(unit)"
        case "health": return "건강 앱으로 채움"
        default: return ActivityStore.format(log.duration)
        }
    }

    /// 수치 습관이면 단위, 아니면 빈 문자열.
    private func unit(for keyID: UUID) -> String {
        guard let key = keys.first(where: { $0.id == keyID }), key.measureStep > 0 else { return "" }
        return key.measureUnit
    }

    private var summary: [SummaryRow] {
        Dictionary(grouping: logs, by: \.keyName)
            .map { name, items in
                let sessions = items.filter { $0.kind == "session" }
                let counters = items.filter { $0.kind == "counter" }
                let health = items.filter { $0.kind == "health" }.count
                var parts: [String] = []
                if !sessions.isEmpty { parts.append(ActivityStore.format(sessions.reduce(0) { $0 + $1.duration })) }
                if let first = counters.first {
                    let unit = unit(for: first.keyID)
                    parts.append(unit.isEmpty ? "\(counters.count)회" : "\(Int(counters.reduce(0) { $0 + $1.amount }))\(unit)")
                }
                if health > 0 { parts.append("건강 앱 \(health)일") }
                return SummaryRow(name: name, value: parts.joined(separator: " · "))
            }
            .sorted { $0.name < $1.name }
    }
}
