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
    @State private var showDetail = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let finished {
                    HabitDoneView(key: key, message: finished, progress: TodayPlan.counts(keys: keys, logs: logs, state: store.state)) {
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
            .switchConfirmation($pending, keys: keys)
            .alert("기록하지 않았어요", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(problem ?? "") }
        }
    }

    private var run: some View {
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
            Spacer(minLength: 0)
            actions
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    /// 한 손으로 누를 수 있게 주 버튼을 아래에 둔다.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if runningSince != nil {
                primary("완료했어요") { stopTimer() }
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
                    primary("휴식 시작 (\(key.countdownMinutes)분)") { startTimer(); dismiss() }
                }
            }
            Button("나중에 하기") { dismiss() }.padding(.top, 4)
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

    private var attendedToday: Bool {
        logs.contains { $0.keyID == key.id && Calendar.current.isDateInToday($0.startedAt) }
    }

    // MARK: - 실행

    private func record(minutes: Int) {
        if let reason = store.addRecord(key, on: .now, minutes: minutes, context: context) {
            problem = reason
            return
        }
        finished = key.isQuit ? "기록했어요. 내일 다시 지켜 봐요." : "좋아요! 오늘의 작은 약속 하나 완료."
    }

    private func startTimer() {
        if case .needsConfirmation(let p) = store.activate(key, keys: keys, context: context) { pending = p }
    }

    /// 진행 중인 세션을 같은 물건으로 다시 실행하면 끝나고 기록된다.
    private func stopTimer() {
        _ = store.activate(key, keys: keys, context: context)
        finished = "좋아요! 오늘의 작은 약속 하나 완료."
    }
}

/// 완료 피드백. 짧게 칭찬하고 오늘 진행을 보여 준 뒤 오늘 화면으로 돌아간다.
struct HabitDoneView: View {
    let key: KeyObject
    let message: String
    let progress: (done: Int, total: Int)
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

/// 오늘 할 일 셈. 홈 "오늘 할 일" 머리글과 같은 기준이다(일정상 오늘이거나 오늘 이미 한 습관).
enum TodayPlan {
    static func isTodo(_ key: KeyObject, _ progress: KeyProgress) -> Bool {
        key.schedule.isDue(on: .now, metToday: progress.metToday, weekDone: progress.weekDone, calendar: .current)
    }

    static func counts(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) -> (done: Int, total: Int) {
        let todo = keys.filter(\.supportsGoal)
            .map { ($0, KeyProgress.of($0, logs: logs, state: state)) }
            .filter { isTodo($0.0, $0.1) }
        return (todo.filter { $0.1.metToday }.count, todo.count)
    }
}
