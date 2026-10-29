import SwiftData
import SwiftUI
import ObjectKeyCore

struct HomeView: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @Query private var logs: [ActivityLog]

    @State private var showScan = false
    @State private var showRegister = false
    @State private var pending: PendingSwitch?
    @State private var editingGoal: KeyObject?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            let tracked = keys.filter(\.supportsGoal).map { (key: $0, progress: KeyProgress.of($0, logs: logs, state: store.state)) }
            let progressByID = Dictionary(uniqueKeysWithValues: tracked.map { ($0.key.id, $0.progress) })
            List {
                if !tracked.isEmpty { MoodHeader(items: tracked) }
                ActiveBanner(state: store.state, keys: keys)

                Section {
                    ForEach(keys) { key in
                        Button { activateManually(key) } label: {
                            KeyRow(key: key, active: store.state.activeKeyID == key.id, progress: progressByID[key.id])
                        }
                        .tint(.primary)
                        .contextMenu {
                            if key.supportsGoal { Button("하루 목표…", systemImage: "target") { editingGoal = key } }
                        }
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("내 물건")
                } footer: {
                    if !keys.isEmpty { Text("행을 누르면 카메라 없이 바로 실행됩니다.") }
                }
            }
            .overlay {
                if keys.isEmpty {
                    ContentUnavailableView {
                        Image(.peek).resizable().scaledToFit().frame(height: 140)
                        Text("아직 등록한 물건이 없어요")
                    } description: {
                        Text("책, 컵, 붓처럼 책상 위 물건에 능력을 부여해 보세요.")
                    } actions: {
                        Button("첫 물건 등록하기") { showRegister = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("MOKI")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { HistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("기록")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRegister = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("물건 등록")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !keys.isEmpty {
                    Button { showScan = true } label: {
                        Label("물건 비추기", systemImage: "viewfinder").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
            }
            .sheet(isPresented: $showRegister) { RegisterView() }
            .sheet(item: $editingGoal) { GoalEditor(key: $0) }
            .fullScreenCover(isPresented: $showScan) { ScanView() }
            .switchConfirmation($pending, keys: keys)
            .resultToast(message: Binding(get: { store.lastMessage }, set: { store.lastMessage = $0 }))
            .onReceive(ticker) { _ in store.tick(keys: keys, context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.tick(keys: keys, context: context) }
            }
        }
    }

    private func activateManually(_ key: KeyObject) {
        if case .needsConfirmation(let p) = store.activate(key, keys: keys, context: context) { pending = p }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.finishIfInvolved(keys[index], keys: keys, context: context)
            context.delete(keys[index])
        }
        try? context.save()
    }
}

struct KeyRow: View {
    let key: KeyObject
    var active = false
    var progress: KeyProgress?

    var body: some View {
        HStack(spacing: 12) {
            KeyBadge(symbol: key.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let progress { ProgressMark(progress: progress) }
            if active { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
        }
        .padding(.vertical, 4)
    }

    /// 오늘 기록이 있으면 동작 이름 대신 진행 상황("오늘 20/30분")을 보여준다.
    private var subtitle: String {
        guard let progress, progress.today > 0 || progress.goal != nil else { return key.action.label }
        return "오늘 " + progress.summary(forCounter: key.actionKind == "counter")
    }
}

/// 진행 중인 세션·휴식 표시.
struct ActiveBanner: View {
    let state: ActivityState
    let keys: [KeyObject]

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .session(let id, _, let segmentStart, let accumulated):
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    banner(id, title: "진행 중", value: ActivityStore.format(accumulated + context.date.timeIntervalSince(segmentStart)))
                }
            } footer: { Text("같은 물건을 다시 비추면 종료하고 기록합니다.") }
        case .countdown(let id, let endsAt, let paused):
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    banner(id, title: "휴식", value: ActivityStore.format(max(0, endsAt.timeIntervalSince(context.date))))
                }
            } footer: {
                if paused != nil { Text("휴식이 끝나면 멈춰 둔 세션이 이어집니다.") }
            }
        }
    }

    private func banner(_ id: UUID, title: String, value: String) -> some View {
        let key = keys.first { $0.id == id }
        return HStack {
            if title == "휴식" {
                Image(.break).resizable().scaledToFit().frame(width: 52, height: 52)
            } else {
                KeyBadge(symbol: key?.emoji ?? "", size: 52)
            }
            VStack(alignment: .leading) {
                Text("\(key?.name ?? "물건") · \(title)").font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.title2.monospacedDigit().bold())
            }
        }
    }
}

extension View {
    /// 다른 활동이 진행 중일 때 전환 여부를 묻는다.
    func switchConfirmation(_ pending: Binding<PendingSwitch?>, keys: [KeyObject], onDone: @escaping () -> Void = {}) -> some View {
        modifier(SwitchConfirmation(pending: pending, keys: keys, onDone: onDone))
    }

    func resultToast(message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Label {
                    Text(text)
                } icon: {
                    Image(.success).resizable().scaledToFit().frame(width: 28, height: 28)
                }
                    .id(text) // 메시지가 바뀌면 아래 task를 다시 시작해 2초를 새로 센다.
                    .font(.callout.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        message.wrappedValue = nil
                    }
            }
        }
        .animation(.spring, value: message.wrappedValue)
    }
}

private struct SwitchConfirmation: ViewModifier {
    @Environment(ActivityStore.self) private var store
    @Environment(\.modelContext) private var context
    @Binding var pending: PendingSwitch?
    let keys: [KeyObject]
    let onDone: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { p in
            Button("전환") {
                store.confirm(p, keys: keys, context: context)
                onDone()
            }
            Button("취소", role: .cancel) { onDone() }
        } message: { _ in
            Text("진행 중인 활동을 끝내고 기록한 뒤 새 활동을 시작합니다.")
        }
    }

    private var title: String {
        guard let p = pending else { return "" }
        let name = { (id: UUID) in keys.first { $0.id == id }?.name ?? "물건" }
        return "\(name(p.from)) → \(name(p.to))"
    }
}
