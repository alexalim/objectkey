import SwiftData
import SwiftUI
import ObjectKeyCore

extension HabitPhase {
    var label: String {
        switch self {
        case .adapting: return "1단계 적응"
        case .wiring: return "2단계 회로 형성"
        case .automating: return "3단계 자동화"
        case .formed: return "습관 안착"
        }
    }

    static let all: [HabitPhase] = [.adapting, .wiring, .automating, .formed]

    var days: String {
        switch self {
        case .adapting: return "1~22일"
        case .wiring: return "23~44일"
        case .automating: return "45~66일"
        case .formed: return "67일~"
        }
    }

    /// 단계별 한 줄 조언.
    var tip: String {
        switch self {
        case .adapting: return "작게라도 시작하는 것만 생각해요."
        case .wiring: return "쉬는 날에도 한 번은 비춰 주세요."
        case .automating: return "이제 몸이 먼저 기억하기 시작해요."
        case .formed: return "66일을 넘겼어요. 이제 내 습관이에요."
        }
    }
}

/// 하루 목표 입력. 세션은 5분 단위, 카운터는 1회 단위. 0이면 목표 없음.
struct GoalStepper: View {
    let actionKind: String
    @Binding var goal: Int

    var body: some View {
        let counter = actionKind == "counter"
        Stepper(goal == 0 ? "목표 없음 (하루 1번 비추기)" : "하루 \(goal)\(counter ? "회" : "분")",
                value: $goal, in: 0...(counter ? 100 : 600), step: counter ? 1 : 5)
    }
}

/// 습관 알림 켜기와 시각. 켤 때 알림 권한을 묻고, 거절되면 다시 끈다. -1이면 끔.
struct ReminderPicker: View {
    @Binding var minute: Int
    @State private var denied = false

    var body: some View {
        Toggle("매일 알림", isOn: Binding(get: { minute >= 0 }, set: { on in
            guard on else { minute = -1; return }
            minute = 9 * 60
            Task {
                denied = !(await HabitReminders.requestPermission())
                if denied { minute = -1 }
            }
        }))
        if minute >= 0 {
            DatePicker("시각", selection: Binding(
                get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minute = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
                displayedComponents: .hourAndMinute)
        }
        if denied {
            Text("알림이 꺼져 있어요. 설정 앱에서 MOKI 알림을 허용해 주세요.").font(.footnote).foregroundStyle(.orange)
        }
    }
}

/// 습관 설정 공통 안내. 등록 화면과 설정 시트가 같은 문구를 쓴다.
enum HabitCopy {
    static let goalFooter = "처음에는 실패할 수 없을 만큼 작게 시작하세요. 목표 없음이면 하루 한 번만 비춰도 이어집니다. 하루 빠지는 건 괜찮지만, 이틀 연속 빠지면 끊겨요."
    static let cuePlaceholder = "이미 하는 행동 (예: 아침 커피 내린)"
    static let cueFooter = "이미 몸에 밴 행동 바로 뒤에 붙이면 잊지 않아요. \"…다음에\"로 표시됩니다."
    static let reminderFooter = "그날 이미 비췄으면 알림은 오지 않아요."
}

/// 등록한 뒤 목표와 신호를 바꾸는 시트. 홈 목록에서 길게 눌러 연다.
struct GoalEditor: View {
    @Bindable var key: KeyObject
    var progress: KeyProgress?
    /// 지금까지 남은 기록 수(세션·카운터 모두 1회로 센다).
    var recordCount = 0
    var days: [Date: DayStatus] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HabitCalendar(days: days)
                } header: {
                    Text("기록 달력")
                }
                HabitGuide(progress: progress, recordCount: recordCount)
                Section {
                    GoalStepper(actionKind: key.actionKind, goal: $key.dailyGoal)
                } header: {
                    Text("하루 목표")
                } footer: {
                    Text(HabitCopy.goalFooter)
                }
                Section {
                    TextField(HabitCopy.cuePlaceholder, text: $key.cue)
                        .submitLabel(.done)
                } header: {
                    Text("언제 할까요? (선택)")
                } footer: {
                    Text(HabitCopy.cueFooter)
                }
                Section {
                    ReminderPicker(minute: $key.reminderMinute)
                } footer: {
                    Text(HabitCopy.reminderFooter)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("\(key.name) 습관 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// 한 달 단위 기록 달력. 채운 날은 진하게, 기록은 있지만 목표에 못 미친 날은 옅게 칠한다.
struct HabitCalendar: View {
    let days: [Date: DayStatus]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        VStack(spacing: 8) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("이전 달")
                Spacer()
                Text(month, format: .dateTime.year().month(.wide)).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(month >= thisMonth)
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: columns, spacing: 4) {
                // 영어 기호는 S·T가 겹치므로 위치로 구분한다.
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { Text($0.element).font(.caption2).foregroundStyle(.secondary) }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] { cell(day) } else { Color.clear.frame(height: 32) }
                }
            }
            HStack(spacing: 12) {
                legend(Color.orange, "채운 날")
                legend(Color.orange.opacity(0.25), "목표 미달")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func cell(_ day: Date) -> some View {
        let status = days[day]
        let isToday = calendar.isDateInToday(day)
        return Text("\(calendar.component(.day, from: day))")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(status == .met ? Color.white : (day > .now ? Color.secondary : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                switch status {
                case .met: Circle().fill(Color.orange)
                case .partial: Circle().fill(Color.orange.opacity(0.25))
                case nil: Color.clear
                }
            }
            .overlay { if isToday { Circle().stroke(Color.accentColor, lineWidth: 1.5) } }
            .accessibilityLabel(Text(day, format: .dateTime.month().day()) + Text(status == .met ? ", 채움" : status == .partial ? ", 목표 미달" : ""))
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(label) }
    }

    /// 달력 첫 요일(지역 설정)에 맞춘 요일 머리글.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// 앞쪽 빈칸(nil)과 그달의 날짜들(0시).
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading)
            + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

/// 습관 설정 맨 위 설명. 66일 단계와 이틀 규칙을 보여주고, 지금 단계를 강조한다.
struct HabitGuide: View {
    let progress: KeyProgress?
    let recordCount: Int

    var body: some View {
        let current = progress?.phase
        Section {
            Text("새 행동이 저절로 나오기까지 평균 66일이 걸린다고 해요(런던대 연구). 그 과정을 세 단계로 나눠 보여 드려요.")
                .font(.subheadline)
            ForEach(HabitPhase.all, id: \.self) { phase in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(phase.days).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.label).font(.subheadline.bold())
                        Text(phase.tip).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if phase == current { Text("지금").font(.caption.bold()).foregroundStyle(.orange) }
                }
            }
            Label("하루 빠지는 건 괜찮아요. 이틀 연속만 피하면 일수가 이어집니다.", systemImage: "flame")
                .font(.footnote)
        } header: {
            Text("습관이 되는 과정")
        } footer: {
            let total = recordCount > 0 ? " 지금까지 \(recordCount)회 기록했어요." : ""
            if let progress, progress.streak > 0 {
                Text((progress.atRisk ? "지금 \(progress.streak)일째예요. 어제 쉬었으니 오늘은 꼭 비춰 주세요." : "지금 \(progress.streak)일째 이어가고 있어요.") + total)
            } else {
                Text("오늘 한 번 비추면 1일째가 시작돼요." + total)
            }
        }
    }
}

/// 오늘 진행률 링과 이어온 일수. 목록 행 오른쪽에 붙는다.
struct ProgressMark: View {
    let progress: KeyProgress

    var body: some View {
        HStack(spacing: 8) {
            if progress.streak > 0 {
                // 오늘 안 하면 끊기는 날은 빨간색으로 알린다.
                Label("\(progress.streak)", systemImage: progress.atRisk ? "flame" : "flame.fill")
                    .font(.subheadline.bold()).foregroundStyle(progress.atRisk ? .red : .orange)
                    .accessibilityLabel(progress.atRisk ? "\(progress.streak)일째, 오늘 안 하면 끊겨요" : "\(progress.streak)일째 이어가는 중")
            }
            if let fraction = progress.fraction {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 4)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(progress.metToday ? Color.green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                .accessibilityLabel("오늘 목표 \(Int(fraction * 100))퍼센트")
            }
        }
    }
}

/// 오늘 상태에 따라 MOKI가 반응하는 홈 상단.
struct MoodHeader: View {
    let items: [(key: KeyObject, progress: KeyProgress)]

    var body: some View {
        let r = reaction
        Section {
            HStack(spacing: 12) {
                Image(r.mood).resizable().scaledToFit().frame(width: 64, height: 64)
                Text(r.message).font(.subheadline)
            }
        }
    }

    private var reaction: (mood: Moki, message: String) {
        // 끊기기 직전인 습관이 가장 먼저다. 이틀 연속만은 막는다.
        if let risky = items.filter(\.progress.atRisk).max(by: { $0.progress.streak < $1.progress.streak }) {
            return (.question, "\(risky.key.name), 어제 쉬었어요. 오늘 비추지 않으면 \(risky.progress.streak)일이 끊겨요.")
        }
        let goals = items.filter { $0.progress.goal != nil }
        let metGoals = goals.filter { $0.progress.metToday }.count
        let activeToday = items.filter { $0.progress.today > 0 }.count
        if !goals.isEmpty, metGoals == goals.count {
            return (.success, "오늘 목표를 모두 채웠어요!")
        }
        if !goals.isEmpty, metGoals > 0 || activeToday > 0 {
            return (.key, "오늘 목표 \(metGoals)/\(goals.count) 달성. 계속 가 볼까요?")
        }
        if activeToday > 0 {
            return (.reading, "오늘도 비추고 있어요. 좋아요!")
        }
        if let best = items.max(by: { $0.progress.streak < $1.progress.streak }),
           let phase = best.progress.phase {
            return (.peek, "\(best.key.name) \(best.progress.streak)일째, \(phase.label). \(phase.tip)")
        }
        return (.scan, "오늘 첫 물건을 비춰 보세요. 작게 시작해도 충분해요.")
    }
}
