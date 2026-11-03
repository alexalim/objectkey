import SwiftUI

@main
struct MOKIWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            TodayView().environmentObject(store)
        }
    }
}

/// 오늘 할 일. 누르면 확인 후 기록한다(실수로 기록되지 않게).
struct TodayView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var confirming: WidgetSnapshot.Item?

    var body: some View {
        NavigationStack {
            Group {
                if let today = store.today, !today.items.isEmpty {
                    List {
                        Section {
                            ForEach(today.items) { item in
                                row(item)
                            }
                        } header: {
                            Text("오늘 \(today.doneCount)/\(today.items.count)")
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("MOKI").font(.headline)
                        Text(store.today == nil ? "아이폰에서 MOKI를 한 번 열어 주세요" : "오늘은 쉬는 날이에요")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("MOKI")
            .confirmationDialog(confirming?.name ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                presenting: confirming) { item in
                Button("기록하기") { store.record(item.id) }
                Button("취소", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func row(_ item: WidgetSnapshot.Item) -> some View {
        let label = HStack {
            Image(systemName: item.done ? "checkmark.circle.fill" : (item.quit == true ? "xmark.circle" : "circle"))
                .foregroundStyle(item.done ? .green : (item.quit == true ? .red : .secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.emoji.isEmpty ? "" : item.emoji + " ")\(item.name)").lineLimit(1)
                if let time = item.time { Text(time).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 2)
            if item.streak > 0 {
                Text("\(item.streak)").font(.caption.bold()).foregroundStyle(item.atRisk ? .red : .orange)
            }
        }
        // 이미 한 것과 끊기 습관은 누를 수 없다(끊기의 기록은 "했다"이므로).
        if item.done || item.quit == true {
            label
        } else {
            Button { confirming = item } label: { label }
        }
    }
}
