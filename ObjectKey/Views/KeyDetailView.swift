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
    @Query(sort: \DayNote.day, order: .reverse) private var allNotes: [DayNote]
    @State private var pending: PendingSwitch?
    @State private var selectedDay: Date?
    @State private var editingGoal = false
    /// 메모를 쓰는 날과 입력 중인 내용.
    @State private var noteDay: Date?
    @State private var noteText = ""

    private let calendar = Calendar.current

    var body: some View {
        let logs = allLogs.filter { $0.keyID == key.id }
        let entries = KeyProgress.entries(key, logs: logs, state: store.state)
        let progress = DailyProgress.evaluate(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar)
        let days = DailyProgress.days(entries, goal: key.goalAmount, calendar: calendar)
        let notes = allNotes.filter { $0.keyID == key.id }
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        KeyBadge(symbol: key.emoji, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.action.label).font(.subheadline)
                            if let habit = habitSummary { Text(habit).font(.caption).foregroundStyle(.secondary) }
                            if HealthMetric(rawValue: key.healthMetric) != nil, HealthSync.hasNoData(key) {
                                Label("건강 앱 값이 안 들어와요. 설정 → MOKI → 건강에서 켜 주세요.",
                                      systemImage: "heart.slash")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            if key.shots.isEmpty {
                                Label("사진 없음 · 아래 버튼·위젯·Siri로 기록", systemImage: "camera.badge.ellipsis")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        // 횟수는 잘못 누른 걸 바로 되돌릴 수 있게 −1을 옆에 둔다.
                        if key.kind == .counter {
                            let today = records(on: .now).count
                            Button { removeLatest(on: .now) } label: {
                                Text(key.measureStep > 0 && !key.isQuit ? "−\(key.measureStep)" : "−1").font(.headline).frame(minWidth: 56).padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .disabled(today == 0)
                            .accessibilityLabel("오늘 기록 1회 빼기")
                        }
                        Button(action: run) {
                            Text(actionLabel).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(attendedToday)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                }
                if key.supportsGoal {
                    Section {
                        HStack {
                            stat("\(progress.streak)일", "연속", tint: progress.atRisk ? .red : .orange)
                            stat("\(DailyProgress.bestStreak(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar))일", "최고 기록")
                            stat(monthRate(entries, logs: logs).map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "이번 달 완료율")
                            stat("\(logs.count)회", "전체 기록")
                        }
                        NavigationLink("통계 보기") { KeyStatsView(key: key) }
                    }
                    Section {
                        HabitCalendar(days: days, schedule: key.schedule, noted: Set(notes.map(\.day)),
                                      slips: key.isQuit ? Set(logs.map { calendar.startOfDay(for: $0.startedAt) }) : []) { selectedDay = $0 }
                    } header: {
                        Text("기록 달력")
                    } footer: {
                        Text("날짜를 누르면 깜빡한 기록을 더하거나 지우고, 그날 메모를 남길 수 있어요.")
                    }
                    if !notes.isEmpty {
                        Section("메모") {
                            ForEach(notes.prefix(10)) { note in
                                Button { openNote(note.day) } label: {
                                    LabeledContent(note.day.formatted(.dateTime.month().day().weekday()), value: note.text)
                                }
                                .tint(.primary)
                            }
                        }
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
                Button(note(on: day) == nil ? "메모 남기기" : "메모 고치기") { openNote(day) }
                let count = records(on: day).count
                if count > 1 {
                    Button(key.kind == .counter ? "1회 빼기" : "마지막 기록 1회 지우기") { removeLatest(on: day) }
                    Button("이날 기록 \(count)회 모두 지우기", role: .destructive) { removeRecords(on: day) }
                } else if count == 1 {
                    Button("이날 기록 지우기", role: .destructive) { removeRecords(on: day) }
                }
                Button("취소", role: .cancel) {}
            } message: { day in
                let count = records(on: day).count
                let memo = note(on: day).map { "\n메모: \($0.text)" } ?? ""
                Text((count == 0 ? "이날은 기록이 없어요." : "이날 기록이 \(count)회 있어요.") + memo)
            }
            .alert(noteDay.map { "\($0.formatted(.dateTime.month().day())) 메모" } ?? "",
                   isPresented: Binding(get: { noteDay != nil }, set: { if !$0 { noteDay = nil } }),
                   presenting: noteDay) { day in
                TextField("예: 출장이라 못 함", text: $noteText)
                Button("저장") { saveNote(on: day) }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("비우고 저장하면 메모가 지워져요.")
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
        let health = HealthMetric(rawValue: key.healthMetric).map { ["건강 앱 \($0.label) \(key.healthTarget)\($0.unit)↑ 자동"] } ?? []
        return ([key.schedule.label] + (cue.isEmpty ? [] : ["\(cue) 다음에"]) + health + key.tags.map { "#\($0)" }).joined(separator: " · ")
    }

    /// 지금 누르면 일어날 일. 진행 중인 세션의 물건이면 종료다.
    private var actionLabel: String {
        if case .session(let id, _, _, _) = store.state, id == key.id { return "종료하고 기록" }
        if case .countdown(_, _, let paused?) = store.state, paused.keyID == key.id { return "휴식 끝내고 이어가기" }
        switch key.action {
        case .session: return "시간 기록 시작"
        case .countdown(let minutes): return "\(minutes)분 휴식 시작"
        case .counter:
            if key.isQuit { return "했어요 (기록)" }
            return key.measureStep > 0 ? "+\(key.measureStep)\(key.measureUnit) 기록" : "+1 기록"
        case .attend(_, let minutes): return attendedToday ? "오늘 참석 완료" : "참석 기록 (\(minutes)분)"
        }
    }

    /// 참석은 하루 한 번만 기록한다.
    private var attendedToday: Bool {
        key.kind == .attend && !records(on: .now).isEmpty
    }

    private func run() {
        if case .needsConfirmation(let p) = store.activate(key, keys: keys, context: context) { pending = p }
    }

    // MARK: - 지난 날 고치기

    /// 세션은 목표 시간만큼(목표가 없으면 10분) 넣어 그날이 채워지게 한다.
    private var addedMinutes: Int {
        if key.kind == .attend { return key.attendMinutes }
        return key.dailyGoal > 0 ? key.dailyGoal : 10
    }

    private var addLabel: String {
        if key.isQuit { return "이날 했어요 (기록 추가)" }
        if key.kind == .counter { return key.measureStep > 0 ? "+\(key.measureStep)\(key.measureUnit) 기록 추가" : "+1 기록 추가" }
        return "\(addedMinutes)분 기록 추가"
    }

    private func records(on day: Date) -> [ActivityLog] {
        allLogs.filter { $0.keyID == key.id && calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    private func addRecord(on day: Date) {
        if let problem = store.addRecord(key, on: day, minutes: addedMinutes, context: context) {
            AppAlert.show("기록하지 않았어요", message: problem)
        }
    }

    /// 이번 달 1일과 처음 시작한 날(등록일·가장 이른 기록) 중 늦은 날부터 센다. 시작 전 날을 놓친 것으로 치지 않기 위해서다.
    private func monthRate(_ entries: [ProgressEntry], logs: [ActivityLog]) -> Double? {
        guard let monthStart = calendar.dateInterval(of: .month, for: .now)?.start else { return nil }
        let began = min(key.createdAt, logs.map(\.startedAt).min() ?? key.createdAt)
        return DailyProgress.completionRate(entries, goal: key.goalAmount, schedule: key.schedule,
                                            since: max(monthStart, began), now: .now, calendar: calendar)
    }

    // MARK: - 메모

    private func note(on day: Date) -> DayNote? {
        let start = calendar.startOfDay(for: day)
        return allNotes.first { $0.keyID == key.id && $0.day == start }
    }

    private func openNote(_ day: Date) {
        noteText = note(on: day)?.text ?? ""
        noteDay = calendar.startOfDay(for: day)
    }

    private func saveNote(on day: Date) {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = note(on: day) {
            if text.isEmpty { context.delete(existing) } else { existing.text = text }
        } else if !text.isEmpty {
            context.insert(DayNote(keyID: key.id, day: calendar.startOfDay(for: day), text: text))
        }
        context.saveOrReport()
    }

    /// 그날 가장 나중 기록 하나만 지운다. 횟수는 −1, 시간 기록은 마지막 한 번.
    private func removeLatest(on day: Date) {
        guard let last = records(on: day).max(by: { $0.startedAt < $1.startedAt }) else { return }
        context.delete(last)
        context.saveOrReport()
    }

    private func removeRecords(on day: Date) {
        records(on: day).forEach { context.delete($0) }
        context.saveOrReport()
    }
}
