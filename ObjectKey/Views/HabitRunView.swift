import SwiftData
import SwiftUI
import ObjectKeyCore

/// 실행 화면. 홈 카드·스캔·알림에서 들어와, 할 일을 보여 주고 사용자가 [완료했어요]를 눌러야 기록한다.
/// 스캔이나 타이머가 끝난 것만으로 완료로 치지 않는다(완료는 사용자가 정한다).
struct HabitRunView: View {
    let key: KeyObject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @Query private var logs: [ActivityLog]
    @State private var pending: PendingSwitch?
    @State private var finished: String?
    /// 이번 완료로 새로 받은 스티커.
    @State private var newSticker: Moki?
    /// 완료 화면의 작은 칩(연속 일수·이번 주·레벨).
    @State private var chips: [DoneChip] = []
    /// 사진 없이 쓰는 습관을 세 번째로 했을 때 한 번, 사진을 찍어 스캔을 켜 보라고 권한다.
    @State private var suggestPhotos = false
    @State private var addingPhotos = false
    @State private var showDetail = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let finished {
                    HabitDoneView(key: key, message: finished, progress: TodayPlan.counts(keys: keys, logs: logs, state: store.state),
                                  sticker: newSticker, chips: chips,
                                  onAddPhotos: suggestPhotos ? { addingPhotos = true } : nil) {
                        dismiss()
                    }
                } else {
                    run
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if finished == nil {
                    ToolbarItem(placement: .primaryAction) { Button("자세히") { showDetail = true } }
                }
            }
            .sheet(isPresented: $showDetail) { KeyDetailView(key: key, keys: keys) }
            .sheet(isPresented: $addingPhotos, onDismiss: { if !key.shots.isEmpty { suggestPhotos = false } }) { AddPhotosView(key: key) }
            .switchConfirmation($pending, keys: keys)
            .alert("기록하지 않았어요", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(problem ?? "") }
        }
    }

    /// 작은 화면·큰 글씨에서도 주 버튼이 밀려나지 않게, 내용은 스크롤하고 버튼은 아래에 고정한다.
    private var run: some View {
        ScrollView {
        VStack(spacing: 16) {
            Text("지금 할 습관").font(.subheadline).foregroundStyle(.secondary)
            KeyBadge(symbol: key.emoji, size: 140)
            Text(key.name).font(.title2.bold())
            if let what = whatToDo { Text(what).font(.headline).foregroundStyle(.tint) }
            let cue = key.cue.trimmingCharacters(in: .whitespaces)
            if !cue.isEmpty { Text("\(cue) 다음에").font(.subheadline).foregroundStyle(.secondary) }
            if let running = runningSince {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ActivityStore.format(running.accumulated + context.date.timeIntervalSince(running.since)))
                        .font(.largeTitle.monospacedDigit().bold())
                }
                Text("다 했으면 완료를 눌러 주세요. 시간이 기록돼요.").font(.footnote).foregroundStyle(.secondary)
            }
            if let ends = countdownEnds {
                Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
                    .font(.largeTitle.monospacedDigit().bold())
                Text("쉬는 중이에요. 끝나면 멈춰 둔 기록이 이어져요.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            actions.padding(.horizontal).padding(.bottom, 8).background(.bar)
        }
    }

    /// 한 손으로 누를 수 있게 주 버튼을 아래에 둔다.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if runningSince != nil {
                primary("완료했어요") { stopTimer() }
            } else if countdownEnds != nil {
                // 같은 물건으로 다시 실행하면 휴식이 끝난다.
                primary("휴식 끝내기") { _ = store.activate(key, keys: keys, context: context); dismiss() }
            } else {
                switch key.kind {
                case .session:
                    primary("완료했어요 (\(sessionMinutes)분)") { record(minutes: sessionMinutes) }
                    Button("타이머로 하기") { startTimer() }.buttonStyle(.bordered).controlSize(.large)
                case .counter:
                    if key.isQuit {
                        Button("했어요 (기록)") { record(minutes: 0) }.buttonStyle(.bordered).controlSize(.large)
                    } else {
                        primary(key.measureStep > 0 ? "완료했어요 (+\(key.measureStep)\(key.measureUnit))" : "완료했어요") { record(minutes: 0) }
                    }
                case .attend:
                    if attendedToday {
                        Label("오늘 참석 완료", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                    } else {
                        primary("참석했어요 (\(key.attendMinutes)분)") { record(minutes: key.attendMinutes) }
                    }
                case .countdown:
                    primary("휴식 시작 (\(key.countdownMinutes)분)") {
                        startTimer()
                        // 다른 휴식을 바꿀지 묻는 창이 떴으면 닫지 않는다.
                        if pending == nil { dismiss() }
                    }
                }
            }
            HStack(spacing: 20) {
                Button("나중에 하기") { dismiss() }
                // 사정이 있는 날은 쉬어도 놓친 날로 치지 않는다.
                if key.supportsGoal, !key.isQuit, !key.isSkipped(.now), runningSince == nil, countdownEnds == nil {
                    Button("오늘은 쉴게요") {
                        key.toggleSkip(.now)
                        context.saveOrReport()
                        WidgetBridge.refreshFromStore()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - 상태

    /// "하루 10분", "하루 3회" 처럼 오늘 할 만큼. 없으면 nil.
    private var whatToDo: String? {
        if key.isQuit { return "오늘은 안 하기" }
        switch key.kind {
        case .session: return key.dailyGoal > 0 ? "하루 \(key.dailyGoal)분" : nil
        case .counter: return key.dailyGoal > 0 ? "하루 \(key.dailyGoal)\(key.countUnit)" : nil
        case .attend: return KeyAction.clock(key.attendStartMinute) + " 시작"
        case .countdown: return nil
        }
    }

    private var sessionMinutes: Int { key.dailyGoal > 0 ? key.dailyGoal : 10 }

    private var runningSince: (since: Date, accumulated: TimeInterval)? {
        if case .session(let id, _, let segmentStart, let accumulated) = store.state, id == key.id {
            return (segmentStart, accumulated)
        }
        return nil
    }

    private var countdownEnds: Date? {
        if case .countdown(let id, let endsAt, _) = store.state, id == key.id { return endsAt }
        return nil
    }

    private var attendedToday: Bool {
        logs.contains { $0.keyID == key.id && Calendar.current.isDateInToday($0.startedAt) }
    }

    // MARK: - 실행

    private func record(minutes: Int) {
        let before = Before.now(key, context: context, state: store.state, fallback: logs)
        if let reason = store.addRecord(key, on: .now, minutes: minutes, context: context) {
            problem = reason
            return
        }
        celebrate(since: before)
    }

    /// 기록 전 모습. 칭찬을 고르려면 기록 뒤와 비교해야 해서, 저장하기 전에 잡아 둔다.
    private struct Before {
        let progress: KeyProgress
        let level: Int
        let lastRecord: Date?

        @MainActor
        static func now(_ key: KeyObject, context: ModelContext, state: ActivityState, fallback: [ActivityLog]) -> Before {
            let all = (try? context.fetch(FetchDescriptor<ActivityLog>())) ?? fallback
            return Before(progress: KeyProgress.of(key, logs: all, state: state),
                          level: HabitLevel.of(score: key.strength(logs: all, state: state) ?? 0).level,
                          lastRecord: all.filter { $0.keyID == key.id }.map(\.startedAt).max())
        }
    }

    /// 방금 기록으로 무엇이 달라졌는지 보고 칭찬 한 줄과 칩, 새 스티커를 정한다. 기록이 저장소에 반영된 뒤 다시 센다.
    private func celebrate(since before: Before) {
        let all = (try? context.fetch(FetchDescriptor<ActivityLog>())) ?? logs
        let state = store.state
        newSticker = Stickers.claimNew(bestStreak: Stickers.bestStreak(keys: keys, logs: all, state: state))
        let after = KeyProgress.of(key, logs: all, state: state)
        let level = HabitLevel.of(score: key.strength(logs: all, state: state) ?? 0).level
        let today = TodayPlan.counts(keys: keys, logs: all, state: state)
        let calendar = Calendar.current
        let gap = before.lastRecord.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: .now)).day
        }
        finished = Praise.message(.init(isQuit: key.isQuit, isFirst: before.lastRecord == nil, daysSinceLast: gap,
                                        wasAtRisk: before.progress.atRisk && !before.progress.metToday,
                                        streakAfter: after.streak, allDoneToday: today.total > 0 && today.done == today.total,
                                        levelBefore: before.level, levelAfter: level, newSticker: newSticker != nil))
        // 세 번 해 봤으면 이 습관을 계속 쓸 사람이다. 그때 한 번만 스캔을 권한다(물건을 같이 쓰는 습관은 주인 사진을 쓴다).
        suggestPhotos = !key.isQuit && key.shots.isEmpty && key.photoSourceID == nil
            && all.filter { $0.keyID == key.id }.count == 3
        // 끊기 습관의 기록은 저지른 날이라 일수·레벨을 자랑하지 않는다. 오늘 개수는 아래 진행 카드가 보여 준다.
        guard !key.isQuit else { chips = []; return }
        chips = [after.streak > 0 ? DoneChip(symbol: "flame.fill", text: "\(after.streak)일째") : nil,
                 after.weekDone > 0 ? DoneChip(symbol: "calendar", text: "이번 주 \(after.weekDone)일") : nil,
                 DoneChip(symbol: "chart.bar.fill", text: "Lv.\(level)")].compactMap { $0 }
    }

    private func startTimer() {
        if case .needsConfirmation(let p) = store.activate(key, keys: keys, context: context) { pending = p }
    }

    /// 진행 중인 세션을 같은 물건으로 다시 실행하면 끝나고 기록된다.
    private func stopTimer() {
        let before = Before.now(key, context: context, state: store.state, fallback: logs)
        _ = store.activate(key, keys: keys, context: context)
        celebrate(since: before)
    }
}

/// 완료 화면의 작은 칩 하나.
struct DoneChip: Hashable {
    let symbol: String
    let text: String
}

/// 완료 피드백. 짧게 칭찬하고 오늘 진행을 보여 준 뒤 오늘 화면으로 돌아간다.
struct HabitDoneView: View {
    let key: KeyObject
    let message: String
    let progress: (done: Int, total: Int)
    var sticker: Moki? = nil
    var chips: [DoneChip] = []
    /// 있으면 "사진 찍어 스캔 켜기" 권유 카드를 보여 준다.
    var onAddPhotos: (() -> Void)? = nil
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(key.isQuit ? .peek : .success).resizable().scaledToFit().frame(height: 180)
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .opacity(shown || reduceMotion ? 1 : 0)
            Text(message).font(.title3.bold()).multilineTextAlignment(.center)
            Text(key.name).foregroundStyle(.secondary)
            if !chips.isEmpty {
                // 큰 글씨에서는 칩이 한 줄에 안 들어가므로 세로로 쌓는다.
                ViewThatFits {
                    HStack(spacing: 8) { chipViews }
                    VStack(spacing: 6) { chipViews }
                }
                .accessibilityElement(children: .combine)
            }
            if let sticker {
                HStack(spacing: 12) {
                    Image(sticker).resizable().scaledToFit().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("새 스티커를 받았어요!").font(.headline)
                        Text("마이 → 스티커 모음에서 볼 수 있어요.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            if let onAddPhotos {
                Button(action: onAddPhotos) {
                    HStack(spacing: 12) {
                        Image(.scan).resizable().scaledToFit().frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("물건 사진을 찍어 둘까요?").font(.headline)
                            Text("다음부터는 물건을 비추기만 해도 바로 열려요.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                .tint(.primary)
            }
            if progress.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("오늘의 진행").font(.subheadline)
                        Spacer()
                        Text("\(progress.done) / \(progress.total)").font(.subheadline.bold().monospacedDigit())
                    }
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("오늘 화면으로").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .sensoryFeedback(.success, trigger: shown)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(duration: 0.3)) { shown = true } }
        }
    }
}

extension HabitDoneView {
    @ViewBuilder
    fileprivate var chipViews: some View {
        ForEach(chips, id: \.self) { chip in
            Label(chip.text, systemImage: chip.symbol)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.orange.opacity(0.14), in: Capsule())
        }
    }
}

/// 오늘 할 일 셈. 홈 "오늘 할 일" 머리글과 같은 기준이다(일정상 오늘이거나 오늘 이미 한 습관).
enum TodayPlan {
    /// 오늘 건너뛰기로 한 습관은 (이미 채웠으면 빼고) 쉬는 날로 내려간다.
    static func isTodo(_ key: KeyObject, _ progress: KeyProgress) -> Bool {
        if key.isSkipped(.now), !progress.metToday { return false }
        return key.schedule.isDue(on: .now, metToday: progress.metToday, weekDone: progress.weekDone, calendar: .current)
    }

    static func counts(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) -> (done: Int, total: Int) {
        let todo = keys.filter(\.supportsGoal)
            .map { ($0, KeyProgress.of($0, logs: logs, state: state)) }
            .filter { isTodo($0.0, $0.1) }
        return (todo.filter { $0.1.metToday }.count, todo.count)
    }
}
