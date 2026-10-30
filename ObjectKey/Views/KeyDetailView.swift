import SwiftData
import SwiftUI
import ObjectKeyCore

/// 목록에서 물건을 누르면 여는 화면. 기록 달력과 통계를 보고, 지금 기록하거나 깜빡한 날을 고친다.
struct KeyDetailView: View {
    let key: KeyObject
    let keys: [KeyObject]
    @Environment(ActivityStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allLogs: [ActivityLog]
    @State private var pending: PendingSwitch?
    @State private var selectedDay: Date?
    @State private var editingGoal = false

    private let calendar = Calendar.current

    var body: some View {
        let logs = allLogs.filter { $0.keyID == key.id }
        let entries = KeyProgress.entries(key, logs: logs, state: store.state)
        let progress = DailyProgress.evaluate(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar)
        let days = DailyProgress.days(entries, goal: key.goalAmount, calendar: calendar)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        KeyBadge(symbol: key.emoji, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.action.label).font(.subheadline)
                            if let habit = habitSummary { Text(habit).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button(action: run) {
                        Text(actionLabel).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                }
                if key.supportsGoal {
                    Section {
                        HStack {
                            stat("\(progress.streak)일", "지금", tint: progress.atRisk ? .red : .orange)
                            stat("\(DailyProgress.bestStreak(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar))일", "최고 기록")
                            stat("\(days.filter { $0.value == .met && calendar.isDate($0.key, equalTo: .now, toGranularity: .month) }.count)일", "이번 달")
                            stat("\(logs.count)회", "전체 기록")
                        }
                    }
                    Section {
                        HabitCalendar(days: days, schedule: key.schedule) { selectedDay = $0 }
                    } header: {
                        Text("기록 달력")
                    } footer: {
                        Text("날짜를 누르면 깜빡한 기록을 더하거나 잘못된 기록을 지울 수 있어요.")
                    }
                    HabitGuide(progress: progress, recordCount: logs.count, schedule: key.schedule)
                }
            }
            .navigationTitle(key.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if key.supportsGoal {
                    ToolbarItem(placement: .primaryAction) {
                        Button("습관 설정", systemImage: "target") { editingGoal = true }
                    }
                }
            }
            .sheet(isPresented: $editingGoal) { GoalEditor(key: key) }
            .confirmationDialog(selectedDay.map { $0.formatted(.dateTime.month().day().weekday()) } ?? "",
                                isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } }),
                                titleVisibility: .visible, presenting: selectedDay) { day in
                Button(addLabel) { addRecord(on: day) }
                let count = records(on: day).count
                if count > 0 {
                    Button("이 날 기록 \(count)건 지우기", role: .destructive) { removeRecords(on: day) }
                }
                Button("취소", role: .cancel) {}
            } message: { day in
                let count = records(on: day).count
                Text(count == 0 ? "이 날은 기록이 없어요." : "이 날 기록 \(count)건이 있어요.")
            }
            .switchConfirmation($pending, keys: keys)
            .resultToast(message: Binding(get: { store.lastMessage }, set: { store.lastMessage = $0 }))
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// "월·수·금 · 커피 내린 다음에". 습관 정보가 없으면 nil.
    private var habitSummary: String? {
        guard key.supportsGoal else { return nil }
        let cue = key.cue.trimmingCharacters(in: .whitespaces)
        return ([key.schedule.label] + (cue.isEmpty ? [] : ["\(cue) 다음에"])).joined(separator: " · ")
    }

    /// 지금 누르면 일어날 일. 진행 중인 세션의 물건이면 종료다.
    private var actionLabel: String {
        if case .session(let id, _, _, _) = store.state, id == key.id { return "종료하고 기록" }
        if case .countdown(_, _, let paused?) = store.state, paused.keyID == key.id { return "휴식 끝내고 이어가기" }
        switch key.action {
        case .session: return "시간 기록 시작"
        case .countdown(let minutes): return "\(minutes)분 휴식 시작"
        case .counter: return "+1 기록"
        }
    }

    private func run() {
        if case .needsConfirmation(let p) = store.activate(key, keys: keys, context: context) { pending = p }
    }

    // MARK: - 지난 날 고치기

    /// 세션은 목표 시간만큼(목표가 없으면 10분) 넣어 그날이 채워지게 한다.
    private var addedMinutes: Int { key.dailyGoal > 0 ? key.dailyGoal : 10 }

    private var addLabel: String {
        key.actionKind == "counter" ? "+1 기록 추가" : "\(addedMinutes)분 기록 추가"
    }

    private func records(on day: Date) -> [ActivityLog] {
        allLogs.filter { $0.keyID == key.id && calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    private func addRecord(on day: Date) {
        // 오늘이면 지금 시각, 지난 날이면 그날 정오로 남긴다.
        let at = calendar.isDateInToday(day) ? Date.now : calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
        let counter = key.actionKind == "counter"
        context.insert(ActivityLog(keyID: key.id, keyName: key.name, kind: counter ? "counter" : "session",
                                   startedAt: at, duration: counter ? 0 : Double(addedMinutes * 60)))
        try? context.save()
    }

    private func removeRecords(on day: Date) {
        records(on: day).forEach { context.delete($0) }
        try? context.save()
    }
}
