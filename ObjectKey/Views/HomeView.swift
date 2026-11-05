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
    @State private var editingGoal: KeyObject?
    /// 목록에서 누른 물건. 바로 기록하지 않고 상세 화면을 연다(실수 방지).
    @State private var detailKey: KeyObject?
    @State private var showAsk = false
    @State private var showHelp = false
    @State private var showTags = false
    /// 홈에서 고른 태그. 빈 문자열이면 전체.
    /// 앱을 열 때마다 전체로 시작한다. 예전에는 마지막 태그를 기억해, 새로 등록한 물건이 안 보이는 혼란이 있었다.
    @State private var tagFilter = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            let allTags = TagRules.all(used: keys.map(\.tags), includeDefaults: false)
            // 고른 태그가 사라졌으면 전체로 본다.
            let filter = allTags.contains(tagFilter) ? tagFilter : ""
            let visible = filter.isEmpty ? keys : keys.filter { $0.tags.contains(filter) }
            let tracked = visible.filter(\.supportsGoal).map { (key: $0, progress: KeyProgress.of($0, logs: logs, state: store.state)) }
            let progressByID = Dictionary(uniqueKeysWithValues: tracked.map { ($0.key.id, $0.progress) })
            // 오늘 할 일: 일정상 오늘 해야 하거나 오늘 이미 한 습관. 시간이 정해진 것부터 시간순.
            let todo = tracked.filter { $0.key.schedule.isDue(on: .now, metToday: $0.progress.metToday,
                                                              weekDone: $0.progress.weekDone, calendar: .current) }
                .map(\.key)
                .sorted { ($0.todoMinute ?? Int.max, $0.createdAt) < ($1.todoMinute ?? Int.max, $1.createdAt) }
            let resting = tracked.map(\.key).filter { key in !todo.contains { $0.id == key.id } }
            let tools = visible.filter { !$0.supportsGoal }
            let doneCount = todo.filter { progressByID[$0.id]?.metToday == true }.count
            List {
                if !allTags.isEmpty {
                    TagFilterBar(tags: allTags, selection: $tagFilter) { showTags = true }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                if !tracked.isEmpty { MoodHeader(items: tracked) { detailKey = $0 } }
                ActiveBanner(state: store.state, keys: keys)

                if !tracked.isEmpty {
                    Section {
                        if todo.isEmpty {
                            Text("오늘은 할 일이 없어요. 쉬는 날이에요.").foregroundStyle(.secondary)
                        }
                        rows(todo, progress: progressByID, asTodo: true)
                    } header: {
                        // 작은 회색 머리글은 눈에 잘 띄지 않아 홈의 주 제목처럼 키운다.
                        HStack(alignment: .firstTextBaseline) {
                            Text(filter.isEmpty ? "오늘 할 일" : "#\(filter) 오늘 할 일").font(.title3.bold()).foregroundStyle(.primary)
                            Spacer()
                            Text("\(doneCount)/\(todo.count)").font(.title3.bold().monospacedDigit())
                                .foregroundStyle(doneCount == todo.count && !todo.isEmpty ? Color.green : Color.secondary)
                        }
                        .textCase(nil)
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            // 고른 태그를 기억하므로, 다른 물건이 사라진 것처럼 보이지 않게 알린다.
                            if !filter.isEmpty, keys.count > visible.count {
                                Button("다른 물건 \(keys.count - visible.count)개는 '전체'에서 보여요 · 전체 보기") { tagFilter = "" }
                                    .font(.footnote.weight(.semibold))
                            }
                            Text("누르면 상세 화면에서 기록할 수 있어요. 오른쪽으로 밀면 습관 설정, 왼쪽은 삭제예요.")
                        }
                    }
                }
                if !resting.isEmpty {
                    Section("오늘은 쉬는 날") { rows(resting, progress: progressByID, asTodo: false) }
                }
                if !tools.isEmpty {
                    Section("휴식 타이머") { rows(tools, progress: progressByID, asTodo: false) }
                }
            }
            .overlay {
                if keys.isEmpty {
                    ContentUnavailableView {
                        Image(.peek).resizable().scaledToFit().frame(height: 140)
                        Text("아직 등록한 물건이 없어요")
                    } description: {
                        Text("책, 컵, 영양제처럼 늘 쓰는 물건을 등록해 보세요.")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("사용 안내")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRegister = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("물건 등록")
                }
                // 툴바 빌더는 #available 분기를 받지 않아 버튼은 늘 두고, 시트 안에서 버전을 가른다.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAsk = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("MOKI에게 말하기")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !keys.isEmpty {
                    Button { showScan = true } label: {
                        Label("물건 스캔", systemImage: "viewfinder").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
            }
            .sheet(isPresented: $showRegister, onDismiss: rescheduleReminders) { RegisterView() }
            .sheet(item: $editingGoal, onDismiss: rescheduleReminders) { GoalEditor(key: $0) }
            .sheet(item: $detailKey, onDismiss: rescheduleReminders) { KeyDetailView(key: $0, keys: keys) }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $showTags) { TagManagerView() }
            .sheet(isPresented: $showAsk, onDismiss: rescheduleReminders) {
                if #available(iOS 26.0, *) {
                    AskMokiView()
                } else {
                    ContentUnavailableView("iOS 26 이상에서 쓸 수 있어요", systemImage: "sparkles",
                                           description: Text("MOKI에게 말하기는 기기 안 AI(Apple Intelligence)로 동작해요."))
                        .presentationDetents([.medium])
                }
            }
            .fullScreenCover(isPresented: $showScan) { ScanView() }
            .resultToast(message: Binding(get: { store.lastMessage }, set: { store.lastMessage = $0 }))
            .onReceive(ticker) { _ in store.tick(keys: keys, context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.tick(keys: keys, context: context)
                    Task { await HealthSync.sync(context: context) }
                    store.syncLiveActivity(keys: keys)
                    rescheduleReminders()
                }
            }
            // 기록이 생기면 오늘 알림을 뺄 수 있다. 스캔 화면에서 기록해도 여기서 반영된다.
            .onChange(of: logs.count) { rescheduleReminders() }
            .onChange(of: keys.count) { old, new in
                // 새로 등록한 물건이 지금 고른 태그에 없으면 전체로 돌려, 등록이 안 된 것처럼 보이지 않게 한다(TestFlight 피드백).
                if new > old, !tagFilter.isEmpty, let newest = keys.max(by: { $0.createdAt < $1.createdAt }),
                   !newest.tags.contains(tagFilter) {
                    tagFilter = ""
                }
                rescheduleReminders()
                // Siri 문구("MOKI에서 영양제 기록")에 들어갈 물건 목록을 갱신한다.
                MokiShortcuts.updateAppShortcutParameters()
            }
        }
    }

    /// 기록·설정이 바뀌면 알림과 홈 화면 위젯을 같이 맞춘다.
    private func rescheduleReminders() {
        WidgetBridge.refresh(keys: keys, logs: logs, state: store.state)
        Task { await HabitReminders.reschedule(keys: keys, logs: logs, state: store.state) }
    }

    /// 목록 한 묶음. 섹션마다 순서가 달라 삭제는 그 묶음 기준으로 처리한다.
    private func rows(_ list: [KeyObject], progress: [UUID: KeyProgress], asTodo: Bool) -> some View {
        ForEach(list) { key in
            Button { detailKey = key } label: {
                KeyRow(key: key, active: store.state.activeKeyID == key.id, progress: progress[key.id],
                       done: asTodo ? progress[key.id]?.metToday ?? false : nil,
                       time: asTodo ? key.todoMinute.map(KeyAction.clock) : nil)
            }
            .tint(.primary)
            .contextMenu {
                if key.supportsGoal { Button("습관 설정…", systemImage: "target") { editingGoal = key } }
            }
            // 오른쪽 밀기는 onDelete가 쓰므로 습관은 왼쪽에서 민다.
            .swipeActions(edge: .leading) {
                if key.supportsGoal {
                    Button("습관", systemImage: "target") { editingGoal = key }.tint(.orange)
                }
            }
        }
        .onDelete { offsets in delete(offsets.map { list[$0] }) }
    }

    private func delete(_ targets: [KeyObject]) {
        for key in targets {
            store.finishIfInvolved(key, keys: keys, context: context)
            let id = key.id
            try? context.delete(model: DayNote.self, where: #Predicate { $0.keyID == id })
            context.delete(key)
        }
        try? context.save()
    }
}

struct KeyRow: View {
    let key: KeyObject
    var active = false
    var progress: KeyProgress?
    /// 오늘 할 일 목록이면 완료 여부. nil이면 체크 표시를 그리지 않는다.
    var done: Bool?
    /// 오늘 할 일의 시각("21:00").
    var time: String?

    var body: some View {
        HStack(spacing: 12) {
            if let done {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(done ? Color.green : Color.secondary)
                    .accessibilityLabel(done ? "오늘 완료" : "오늘 아직")
            }
            KeyBadge(symbol: key.emoji)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key.name).font(.headline)
                    if let time { Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if let habitLine { Text(habitLine).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let progress { ProgressMark(progress: progress) }
            if active { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
        }
        .padding(.vertical, 4)
    }

    /// 오늘 기록이 있으면 동작 이름 대신 진행 상황("오늘 20/30분")을 보여준다.
    private var subtitle: String {
        if key.isQuit, let progress { return progress.metToday ? "오늘 지키는 중" : "오늘은 했어요" }
        guard let progress, progress.today > 0 || progress.goal != nil else { return key.actionTitle }
        return "오늘 " + progress.summary(forCounter: key.kind == .counter, unit: key.countUnit)
    }

    /// "월·수·금 · 커피 내린 다음에 · 12일째 1단계 적응". 모두 없으면 nil.
    private var habitLine: String? {
        let cue = key.cue.trimmingCharacters(in: .whitespaces)
        let schedule: String? = switch key.schedule {
        case .daily: nil
        case .weekdays: key.schedule.label
        case .perWeek(let n): "이번 주 \(progress?.weekDone ?? 0)/\(n)회"
        }
        let parts = [
            schedule,
            cue.isEmpty ? nil : "\(cue) 다음에",
            progress.flatMap { p in p.phase.map { "\(p.streak)일째 \($0.label)" } },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                    let elapsed = accumulated + context.date.timeIntervalSince(segmentStart)
                    VStack(alignment: .leading, spacing: 8) {
                        banner(id, title: "진행 중", value: ActivityStore.format(elapsed))
                        if let line = routineLine(id, elapsed: elapsed) {
                            Label(line, systemImage: "list.number").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                    }
                }
            } footer: { Text("다시 스캔하거나 상세 화면에서 끝내면 기록돼요.") }
        case .countdown(let id, let endsAt, let paused):
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    banner(id, title: "휴식", value: ActivityStore.format(max(0, endsAt.timeIntervalSince(context.date))))
                }
            } footer: {
                if paused != nil { Text("휴식이 끝나면 멈춰 둔 시간 기록이 이어져요.") }
            }
        }
    }

    /// 단계별 루틴이면 "2/3 양치 · 1:40 남음", 다 끝났으면 끝 안내.
    private func routineLine(_ id: UUID, elapsed: TimeInterval) -> String? {
        guard let key = keys.first(where: { $0.id == id }) else { return nil }
        let steps = Routine.steps(key.routineSteps)
        guard !steps.isEmpty else { return nil }
        let p = Routine.progress(steps, elapsed: elapsed)
        if p.isFinished { return "루틴 끝! 다시 스캔하거나 상세 화면에서 끝내요" }
        let r = Int(p.remaining)
        return "\(p.index + 1)/\(steps.count) \(steps[p.index].name) · \(r / 60):\(String(format: "%02d", r % 60)) 남음"
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
            Text("하던 기록을 저장하고 새로 시작해요.")
        }
    }

    private var title: String {
        guard let p = pending else { return "" }
        let name = { (id: UUID) in keys.first { $0.id == id }?.name ?? "물건" }
        return "\(name(p.from)) → \(name(p.to))"
    }
}

extension KeyObject {
    /// 오늘 할 일에서 시간순 정렬·표시에 쓰는 시각. 참석은 시작 시각, 그 밖에는 알림 시각.
    var todoMinute: Int? {
        if kind == .attend { return attendStartMinute }
        return reminderMinute >= 0 ? reminderMinute : nil
    }
}
