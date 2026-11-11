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
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirming: WidgetSnapshot.Item?

    var body: some View {
        NavigationStack {
            Group {
                if store.today?.locked == true {
                    notice("워치는 MOKI 플러스에서 쓸 수 있어요. 아이폰 MOKI → 마이에서 열 수 있어요.",
                           hint: "이미 플러스를 샀다면 새로고침을 눌러 주세요.")
                } else if let today = store.today, !today.items.isEmpty {
                    List {
                        Section {
                            ForEach(today.items) { item in
                                row(item)
                            }
                        } header: {
                            Text("오늘 \(today.doneCount)/\(today.items.count)")
                        }
                    }
                } else if store.today == nil {
                    notice("아이폰에서 MOKI를 한 번 열어 주세요", hint: "아이폰이 가까이 있으면 새로고침으로도 받아요.")
                } else {
                    notice("오늘은 쉬는 날이에요", hint: nil)
                }
            }
            .navigationTitle("MOKI")
            // 열 때마다 아이폰에 최신 목록을 요청한다. 아이폰 앱을 열어 두지 않아도 최신 상태가 된다.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { store.requestSnapshot() }
            }
            .confirmationDialog(confirming?.name ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                presenting: confirming) { item in
                Button("기록하기") { store.record(item.id) }
                Button("취소", role: .cancel) {}
            }
        }
    }

    /// 목록이 없을 때의 안내. 왜 없는지와 어떻게 하면 되는지, 그리고 새로고침 버튼.
    private func notice(_ text: String, hint: String?) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("MOKI").font(.headline)
                Text(text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                Button("새로고침", systemImage: "arrow.clockwise") { store.requestSnapshot() }
                    .font(.footnote)
                if let at = store.receivedAt {
                    Text("마지막 수신 \(at.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
                }
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
