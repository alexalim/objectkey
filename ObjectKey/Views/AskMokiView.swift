import SwiftData
import SwiftUI
import ObjectKeyCore

/// 자연어로 미리 채운 등록 화면 값.
struct RegisterDraft: Identifiable {
    let id = UUID()
    var name = ""
    var emoji = ""
    var kind = "session"
    var countdownMinutes = 5
    var goal = 0
    var cue = ""
    var reminderMinute = -1
    var schedule: HabitSchedule = .daily
    var attendStart = 21 * 60
    var attendMinutes = 90
    var tags: [String] = []
}

/// 자연어로 확인을 받은 뒤 남길 기록.
struct RecordPlan: Identifiable {
    let id = UUID()
    let key: KeyObject
    let daysAgo: Int
    /// 횟수 물건이면 횟수, 그 밖에는 분.
    let amount: Int

    var summary: String {
        let day = daysAgo == 0 ? "오늘" : daysAgo == 1 ? "어제" : daysAgo == 2 ? "그저께" : "\(daysAgo)일 전"
        let what: String
        switch key.kind {
        case .counter: what = "+\(amount)회"
        case .attend: what = "참석 (\(amount)분)"
        case .session, .countdown: what = "\(amount)분"
        }
        return "\(key.name) · \(day) · \(what)"
    }
}

/// "한 문장으로 적기": 한 문장으로 등록·기록·질문. 기기 안 AI만 쓴다.
@available(iOS 26.0, *)
struct AskMokiView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @Query private var logs: [ActivityLog]
    @Query private var notes: [DayNote]

    @State private var input = ""
    @State private var busy = false
    @State private var answer: String?
    @State private var problem: String?
    @State private var draft: RegisterDraft?
    @State private var plan: RecordPlan?
    @State private var recorded: String?
    /// 미리 채운 등록 화면에서 저장했는지. 저장했으면 이 창도 닫고 홈으로 간다(TestFlight 피드백).
    @State private var registered = false
    @FocusState private var focused: Bool

    private let examples = [
        "화요일 밤 9시 아이스하키 수업 90분, 30분 전에 알려줘",
        "이번 달 영양제 몇 번 먹었어?",
        "어제 책 30분 읽었어",
    ]

    var body: some View {
        NavigationStack {
            Form {
                if let reason = MokiAssistant.unavailableReason {
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } footer: {
                        Text("휴대폰 안의 AI(Apple Intelligence)로만 처리해서, 적은 문장을 어디에도 보내지 않아요.")
                    }
                } else {
                    Section {
                        TextField("예: 매일 아침 커피 내린 다음에 영양제", text: $input, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($focused)
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                if busy { ProgressView() }
                                Text(busy ? "생각하는 중…" : "보내기").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        Text("등록하기, 지난 기록 남기기, 기록 묻기를 한 문장으로 할 수 있어요. 적은 문장은 휴대폰 안에서만 처리해요.")
                    }
                    if let answer {
                        Section("MOKI") { Text(answer) }
                    }
                    if let recorded {
                        Section { Label(recorded, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "questionmark.circle").foregroundStyle(.orange) }
                    }
                    Section("이렇게 적어 보세요") {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { input = example }.tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("한 문장으로 적기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(item: $draft, onDismiss: { if registered { dismiss() } }) {
                RegisterView(draft: $0, onSaved: { registered = true })
            }
            .confirmationDialog(plan?.summary ?? "", isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }),
                                titleVisibility: .visible, presenting: plan) { plan in
                Button("기록하기") { record(plan) }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("이대로 기록할까요?")
            }
        }
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focused = false
        busy = true
        answer = nil; problem = nil; recorded = nil
        defer { busy = false }
        let today = Date.now.formatted(.dateTime.year().month().day().weekday(.wide))
        do {
            let command = try await MokiAssistant.interpret(text, keyNames: keys.map(\.name), today: today)
            switch command.kind {
            case .register:
                draft = makeDraft(command, text: text)
            case .record:
                makePlan(command, text: text)
            case .question:
                let facts = HabitFacts.text(keys: keys, logs: logs, notes: notes, state: store.state)
                answer = try await MokiAssistant.answer(text, facts: facts)
            }
        } catch {
            problem = "이해하지 못했어요. 조금 다르게 적어 주세요."
        }
    }

    // MARK: - 등록

    /// 원문에서 규칙으로 읽히는 값(요일·시각·길이·알림)을 먼저 쓰고, 모델 값은 빈칸을 채울 때만 쓴다.
    /// TestFlight에서 모델이 문장 전체를 이름에 넣고 휴식 5분으로 등록한 일이 있었다.
    private func makeDraft(_ c: MokiCommand, text: String) -> RegisterDraft {
        var d = RegisterDraft()
        let modelName = CommandResolver.cleanName(c.name ?? "")
        let textName = CommandResolver.cleanName(text)
        // 모델 이름이 비었거나 원문을 거의 그대로 옮겼으면 원문에서 정리한 이름을 쓴다.
        d.name = modelName.isEmpty || modelName.count > 20 || (c.name ?? "").count >= text.count - 2 ? textName : modelName
        if let e = c.emoji?.first, e.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { d.emoji = String(e) }
        let start = CommandResolver.extractStart(text) ?? CommandResolver.minuteOfDay(c.startTime)
        let duration = CommandResolver.extractDuration(text) ?? c.minutes
        let before = CommandResolver.extractRemindBefore(text) ?? c.remindBeforeMinutes
        let modelAction: String? = c.action.map {
            switch $0 {
            case .counter: return "counter"
            case .attend: return "attend"
            case .countdown: return "countdown"
            case .session: return "session"
            }
        }
        d.kind = CommandResolver.inferAction(text: text, model: modelAction, hasStart: start != nil, hasDuration: duration != nil)
        switch d.kind {
        case "attend":
            d.attendStart = start ?? d.attendStart
            d.attendMinutes = duration.map { min(max(($0 + 7) / 15 * 15, 15), 300) } ?? 60
        case "countdown":
            if let m = duration { d.countdownMinutes = min(max(m, 1), 60) }
        case "counter":
            d.goal = min(max(CommandResolver.extractCount(text) ?? c.count ?? 0, 0), 100)
        default:
            if let m = duration { d.goal = min(max((m + 2) / 5 * 5, 0), 600) }
        }
        let days = CommandResolver.extractWeekdays(text)
        d.schedule = CommandResolver.schedule(weekdays: days.isEmpty ? CommandResolver.weekdays(c.weekdays) : days,
                                              timesPerWeek: c.timesPerWeek)
        d.reminderMinute = CommandResolver.reminderMinute(start: d.kind == "attend" ? d.attendStart : start,
                                                          reminder: CommandResolver.minuteOfDay(c.reminderTime),
                                                          before: before)
        d.cue = (c.cue ?? "").trimmingCharacters(in: .whitespaces)
        d.tags = TagRules.mentioned(in: text, known: TagRules.all(used: keys.map(\.tags)))
        return d
    }

    // MARK: - 기록

    private func makePlan(_ c: MokiCommand, text: String) {
        let pairs = keys.map { (id: $0.id, name: $0.name) }
        // 모델이 고른 이름이 안 맞으면 원문 전체로 다시 찾는다.
        guard let id = c.name.flatMap({ CommandResolver.matchKey($0, among: pairs) }) ?? CommandResolver.matchKey(text, among: pairs),
              let key = keys.first(where: { $0.id == id }) else {
            problem = "어떤 물건인지 찾지 못했어요. 등록한 이름으로 적어 주세요."
            return
        }
        let amount: Int
        switch key.kind {
        case .counter: amount = min(max(CommandResolver.extractCount(text) ?? c.count ?? 1, 1), 20)
        case .attend: amount = key.attendMinutes
        case .countdown:
            problem = "휴식 타이머는 기록이 남지 않아요."
            return
        case .session: amount = min(max(CommandResolver.extractDuration(text) ?? c.minutes ?? (key.dailyGoal > 0 ? key.dailyGoal : 10), 1), 600)
        }
        plan = RecordPlan(key: key, daysAgo: CommandResolver.extractDaysAgo(text) ?? CommandResolver.recordDaysAgo(c.daysAgo), amount: amount)
    }

    /// 상세 화면의 "기록 추가"와 같은 규칙: 지난 날은 정오, 참석은 하루 한 번.
    private func record(_ plan: RecordPlan) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -plan.daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
        if let reason = store.addRecord(plan.key, on: day, count: plan.amount, minutes: plan.amount, context: context) {
            problem = reason
            return
        }
        recorded = "\(plan.summary) 기록했어요"
        input = ""
    }
}
