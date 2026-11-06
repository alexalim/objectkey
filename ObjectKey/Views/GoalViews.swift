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
        case .adapting: return "작게라도 시작만 하면 돼요."
        case .wiring: return "고비인 시기예요. 두 번 연속만 피하면 돼요."
        case .automating: return "이제 몸이 먼저 기억하기 시작해요."
        case .formed: return "66일을 넘겼어요. 아직 어색해도 괜찮아요, 계속 이어가면 돼요."
        }
    }
}

/// 하루 목표 입력. 세션은 5분 단위, 카운터는 1회 단위. 0이면 목표 없음.
struct GoalStepper: View {
    let counter: Bool
    @Binding var goal: Int
    /// 수치 습관이면 한 번에 더하는 양과 단위. 목표도 그 단위로 늘린다.
    var measureStep = 0
    var measureUnit = ""

    var body: some View {
        let step = counter ? max(measureStep, 1) : 5
        let unit = counter ? (measureStep > 0 ? measureUnit : "회") : "분"
        Stepper(goal == 0 ? "목표 없음 (한 번만 해도 채움)" : "하루 \(goal)\(unit)",
                value: $goal, in: 0...(counter ? 100 * step : 600), step: step)
    }
}

/// 수치 습관: 한 번 기록할 때 더하는 양과 단위. 단위를 비우면 그냥 횟수다.
struct MeasureEditor: View {
    @Binding var step: Int
    @Binding var unit: String

    var body: some View {
        TextField("단위 (선택, 예: ml, 쪽, km)", text: $unit)
        if !unit.trimmingCharacters(in: .whitespaces).isEmpty {
            Stepper("한 번에 \(max(step, 1))\(unit)", value: Binding(get: { max(step, 1) }, set: { step = $0 }), in: 1...1000,
                    step: max(step, 1) >= 100 ? 50 : (max(step, 1) >= 10 ? 5 : 1))
        }
    }
}

/// 자정부터 분으로 저장하는 시각 고르기.
struct TimeOfDayPicker: View {
    let title: String
    @Binding var minute: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minute = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
            displayedComponents: .hourAndMinute)
    }
}

/// 단계별 루틴 편집. 단계 이름과 분을 차례로 쌓는다.
struct RoutineEditor: View {
    @Binding var stored: [String]
    @State private var name = ""
    @State private var minutes = 3
    @State private var plus = PlusStore.shared

    var body: some View {
        // 플러스 기능. 이미 만들어 둔 루틴은 무료여도 그대로 고칠 수 있다.
        if plus.isPlus || !stored.isEmpty { editor } else { PlusLockRow(title: "단계별 루틴") }
    }

    @ViewBuilder
    private var editor: some View {
        let steps = Routine.steps(stored)
        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
            LabeledContent("\(i + 1). \(step.name)", value: "\(step.minutes)분")
        }
        .onDelete { offsets in
            var list = steps
            list.remove(atOffsets: offsets)
            stored = list.map(\.stored)
        }
        HStack {
            TextField("단계 이름 (예: 세수)", text: $name)
            Stepper("\(minutes)분", value: $minutes, in: 1...120).fixedSize()
        }
        Button("단계 추가", systemImage: "plus") {
            let trimmed = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: " ")
            guard !trimmed.isEmpty else { return }
            stored.append(RoutineStep(name: trimmed, minutes: minutes).stored)
            name = ""
        }
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        if !steps.isEmpty {
            Text("모두 \(Routine.totalMinutes(steps))분").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// 건강 앱 자동 완료: 무엇을, 하루 얼마 이상이면 완료로 볼지.
struct HealthLinkEditor: View {
    @Binding var metric: String
    @Binding var target: Int
    /// nil이면 아직 확인 전. true면 권한 창을 띄울 수 있고, false면 이미 물어봤다.
    @State private var canAsk: Bool?
    @Environment(\.openURL) private var openURL
    @State private var plus = PlusStore.shared

    var body: some View {
        // 플러스 기능. 이미 연결해 둔 건 무료여도 그대로 둔다.
        if plus.isPlus || !metric.isEmpty { editor } else { PlusLockRow(title: "건강 앱 자동 완료") }
    }

    @ViewBuilder
    private var editor: some View {
        Picker("건강 앱", selection: Binding(get: { metric }, set: { new in
            metric = new
            if let m = HealthMetric(rawValue: new) { target = m.defaultTarget }
        })) {
            Text("사용 안 함").tag("")
            ForEach(HealthMetric.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
        }
        if let m = HealthMetric(rawValue: metric) {
            Stepper("하루 \(target)\(m.unit) 이상", value: $target, in: m.targetStep...(m == .steps ? 50000 : 600), step: m.targetStep)
            permissionRow(m)
                .task(id: metric) { canAsk = await HealthSync.shouldAsk(m) }
        }
    }

    /// 권한을 화면에서 보이게 받는다. 처음이면 Apple 건강 권한 창을 띄우고, 이미 물어봤으면 건강 앱에서 바꾸는 길을 알려 준다.
    @ViewBuilder
    private func permissionRow(_ m: HealthMetric) -> some View {
        if !HealthSync.isAvailable {
            Label("이 기기에서는 건강 앱을 쓸 수 없어요.", systemImage: "heart.slash").foregroundStyle(.secondary)
        } else if canAsk == true {
            VStack(alignment: .leading, spacing: 6) {
                Label("건강 앱의 \(m.label)를 읽으려면 권한이 필요해요.", systemImage: "heart.text.square")
                    .font(.subheadline)
                Button {
                    Task {
                        await HealthSync.requestAccess(m)
                        canAsk = await HealthSync.shouldAsk(m)
                    }
                } label: {
                    Label("권한 허용하기", systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("다음 화면에서 '\(m.label)'를 켜고 '허용'을 눌러 주세요.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if canAsk == false {
            VStack(alignment: .leading, spacing: 6) {
                Label("권한 창은 한 번만 떠요. 설정에서 바꿀 수 있어요.", systemImage: "heart.text.square")
                    .font(.subheadline)
                Text("설정 → MOKI → 건강 → '\(m.label)' 켜기")
                    .font(.caption).foregroundStyle(.secondary)
                // 건강 앱 안의 MOKI 권한 화면으로 바로 가는 공개 링크가 없어, 가장 가까운 설정 앱의 MOKI 화면을 연다.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("설정에서 건강 권한 열기", systemImage: "gearshape").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("'건강'이 안 보이면: 건강 앱 → 프로필 → 개인정보 보호 → 앱 → MOKI")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

/// 정해진 시간 참석의 시작 시각과 길이.
struct AttendEditor: View {
    @Binding var startMinute: Int
    @Binding var minutes: Int

    var body: some View {
        TimeOfDayPicker(title: "시작", minute: $startMinute)
        Stepper("\(minutes)분 (\(KeyAction.clock(startMinute + minutes))에 끝)", value: $minutes, in: 15...300, step: 15)
    }
}

/// 습관 알림 켜기와 시각. 켤 때 알림 권한을 묻고, 거절되면 다시 끈다. -1이면 끔.
struct ReminderPicker: View {
    @Binding var minute: Int
    /// 켤 때 처음 잡히는 시각. 참석이면 시작 30분 전.
    var defaultMinute = 9 * 60
    @State private var denied = false

    var body: some View {
        Toggle("매일 알림", isOn: Binding(get: { minute >= 0 }, set: { on in
            guard on else { minute = -1; return }
            minute = defaultMinute
            Task {
                denied = !(await HabitReminders.requestPermission())
                if denied { minute = -1 }
            }
        }))
        if minute >= 0 {
            TimeOfDayPicker(title: "시각", minute: $minute)
        }
        if denied {
            Text("알림이 꺼져 있어요. 설정 앱에서 MOKI 알림을 허용해 주세요.").font(.footnote).foregroundStyle(.orange)
        }
    }
}

extension HabitSchedule {
    /// "매일", "월·수·금", "주 3회".
    var label: String {
        switch self {
        case .daily: return "매일"
        case .weekdays(let days):
            let calendar = Calendar.current
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }.filter(days.contains)
            return ordered.isEmpty ? "매일" : ordered.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: "·")
        case .perWeek(let n): return "주 \(n)회"
        }
    }
}

/// 매일 / 요일 지정 / 주 N회 고르기.
struct ScheduleEditor: View {
    @Binding var schedule: HabitSchedule
    private let calendar = Calendar.current

    private enum Kind: Hashable { case daily, weekdays, perWeek }

    var body: some View {
        Picker("일정", selection: Binding(get: { kind }, set: { new in
            guard new != kind else { return }
            switch new {
            case .daily: schedule = .daily
            case .weekdays: schedule = .weekdays([2, 4, 6])
            case .perWeek: schedule = .perWeek(3)
            }
        })) {
            Text("매일").tag(Kind.daily)
            Text("요일 지정").tag(Kind.weekdays)
            Text("주 N회").tag(Kind.perWeek)
        }
        .pickerStyle(.segmented)
        switch schedule {
        case .daily:
            EmptyView()
        case .weekdays(let days):
            HStack(spacing: 6) {
                ForEach((0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }, id: \.self) { weekday in
                    let on = days.contains(weekday)
                    Button {
                        var next = days
                        if on { next.remove(weekday) } else { next.insert(weekday) }
                        if !next.isEmpty { schedule = .weekdays(next) } // 하나는 남긴다.
                    } label: {
                        Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(Circle().fill(on ? Color.orange : Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        case .perWeek(let n):
            Stepper("일주일에 \(n)번", value: Binding(get: { n }, set: { schedule = .perWeek($0) }), in: 1...6)
        }
    }

    private var kind: Kind {
        switch schedule {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .perWeek: return .perWeek
        }
    }
}

/// 습관 쌓기 신호 입력. "[아침 커피 내린] 다음에"처럼 문장으로 읽히게, 칸 뒤에 "다음에"를 붙여 둔다.
struct CueField: View {
    @Binding var cue: String

    var body: some View {
        HStack(spacing: 6) {
            TextField(HabitCopy.cuePlaceholder, text: $cue)
                .submitLabel(.done)
            Text("다음에").foregroundStyle(.secondary)
        }
    }
}

/// 습관 설정 공통 안내. 등록 화면과 설정 시트가 같은 문구를 쓴다.
enum HabitCopy {
    static let goalFooter = "실패할 수 없을 만큼 작게 시작해요. 목표가 없으면 한 번만 기록해도 채워져요."
    static let cuePlaceholder = "예: 아침 커피 내린"
    static let cueFooter = "매일 하는 행동 바로 뒤에 붙이면 덜 잊어요."
    static let routineFooter = "시작하면 지금 단계와 남은 시간을 보여 주고, 단계가 바뀔 때 알려 줘요. 예: 세수 3분 → 양치 2분 → 스트레칭 5분."
    static let healthFooter = "건강 앱 기록이 목표를 넘으면 그날을 자동으로 채워요. 앱을 열 때 최근 7일을 확인해요. 건강 기록은 읽기만 하고 어디에도 보내지 않아요."
    static let quitFooter = "했을 때만 기록해요. 기록이 없는 날이 지킨 날이에요. 한 번 했어도 이어지고, 이틀 연속이면 끊겨요."
    static let measureFooter = "단위를 쓰면 완료할 때마다 정한 양만큼 더해져요. 예: 물 250ml, 책 10쪽."
    static let attendFooter = "[참석했어요]나 알림의 '참석'을 누르면 정한 시간만큼 바로 기록돼요. 시작·종료를 따로 하지 않아도 되고, 진행 중인 다른 기록도 멈추지 않아요."
    static let reminderFooter = "그날 이미 기록했으면 알림이 오지 않아요. 요일 지정은 정한 요일에만 오고, 주 N회는 그 주를 채우면 멈춰요."

    /// 이틀 규칙을 일정에 맞게 풀어 쓴 문구.
    static func rule(_ schedule: HabitSchedule) -> String {
        switch schedule {
        case .daily: return "하루 빠져도 괜찮아요. 이틀 연속만 피하면 이어져요."
        case .weekdays: return "정한 요일을 한 번 놓쳐도 괜찮아요. 두 번 연속만 피하면 이어지고, 다른 요일에 해도 쳐 줘요."
        case .perWeek: return "한 주를 못 채워도 괜찮아요. 두 주 연속만 피하면 이어져요."
        }
    }

    /// 끊기기 직전 안내. 홈 상단·알림·상세가 같이 쓴다.
    /// 무엇이 잘못됐는지보다 "무엇을 하면 이어지는지"를 먼저 말한다.
    static func risk(_ schedule: HabitSchedule, streak: Int, weekDone: Int = 0, quit: Bool = false) -> String {
        // 다그치지 않는다. 한 번 놓친 건 괜찮다는 말을 먼저 하고, 무엇을 하면 이어지는지 알려 준다.
        if quit { return "어제 한 번은 괜찮아요. 오늘 참으면 \(streak)일이 그대로 이어져요." }
        switch schedule {
        case .daily: return "어제 쉬었어도 괜찮아요. 오늘 한 번이면 \(streak)일이 그대로 이어져요."
        case .weekdays: return "지난번은 쉬었어도 괜찮아요. 오늘 하면 \(streak)일이 그대로 이어져요."
        case .perWeek(let n):
            let remaining = max(1, n - weekDone)
            // 숫자는 한 가지만. 횟수·일·주가 섞이면 읽기 어렵다.
            return "지난주는 괜찮아요. 이번 주 \(remaining)번만 더 하면 이어져요."
        }
    }
}

/// 등록한 뒤 일정·목표·신호·알림을 바꾸는 시트. 물건 상세 화면이나 목록 행 밀기로 연다.
struct GoalEditor: View {
    @Bindable var key: KeyObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TagPicker(tags: $key.tags)
                } header: {
                    Text("태그")
                }
                if key.isQuit {
                    Section {
                        Label("끊기 습관", systemImage: "nosign")
                    } footer: {
                        Text(HabitCopy.quitFooter)
                    }
                } else {
                Section {
                    ScheduleEditor(schedule: $key.schedule)
                } header: {
                    Text("얼마나 자주")
                } footer: {
                    Text(HabitCopy.rule(key.schedule))
                }
                if key.kind == .session {
                    Section {
                        RoutineEditor(stored: $key.routineSteps)
                    } header: {
                        Text("단계별 루틴 (선택)")
                    } footer: {
                        Text(HabitCopy.routineFooter)
                    }
                }
                Section {
                    HealthLinkEditor(metric: $key.healthMetric, target: $key.healthTarget)
                } header: {
                    Text("건강 앱으로 자동 완료 (선택)")
                } footer: {
                    Text(HabitCopy.healthFooter)
                }
                if key.kind == .counter {
                    Section {
                        MeasureEditor(step: $key.measureStep, unit: $key.measureUnit)
                            // 단위가 바뀌면 예전 목표(예: 2000ml)가 새 단위(2000쪽)로 남지 않게 비운다.
                            .onChange(of: key.measureUnit) { _, _ in key.dailyGoal = 0 }
                    } header: {
                        Text("한 번에 얼마나 (선택)")
                    } footer: {
                        Text(HabitCopy.measureFooter)
                    }
                }
                if key.kind == .attend {
                    Section {
                        AttendEditor(startMinute: $key.attendStartMinute, minutes: $key.attendMinutes)
                    } header: {
                        Text("정해진 시간")
                    } footer: {
                        Text(HabitCopy.attendFooter)
                    }
                } else {
                    Section {
                        GoalStepper(counter: key.kind == .counter, goal: $key.dailyGoal,
                                    measureStep: key.measureStep, measureUnit: key.measureUnit)
                    } header: {
                        Text("하루 목표")
                    } footer: {
                        Text(HabitCopy.goalFooter)
                    }
                }
                Section {
                    CueField(cue: $key.cue)
                } header: {
                    Text("언제 할까요? (선택)")
                } footer: {
                    Text(HabitCopy.cueFooter)
                }
                Section {
                    ReminderPicker(minute: $key.reminderMinute,
                                   defaultMinute: key.kind == .attend ? max(0, key.attendStartMinute - 30) : 9 * 60)
                } footer: {
                    Text(HabitCopy.reminderFooter)
                }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("\(key.name) 습관 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 한 달 단위 기록 달력. 채운 날은 진하게, 기록은 있지만 목표에 못 미친 날은 옅게 칠한다.
struct HabitCalendar: View {
    let days: [Date: DayStatus]
    var schedule: HabitSchedule = .daily
    /// 건너뛴 날(0시). 점선 테로 표시한다. 놓친 날이 아니라 쉰 날이다.
    var skipped: Set<Date> = []
    /// 메모가 있는 날(0시). 숫자 아래 작은 점으로 표시한다.
    var noted: Set<Date> = []
    /// 끊기 습관에서 저지른 날(0시). 빨간 테로 표시한다.
    var slips: Set<Date> = []
    /// 날짜를 누르면 부른다. nil이면 보기만 한다. 오늘 이후 날짜는 누를 수 없다.
    var onSelect: ((Date) -> Void)? = nil
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
                    if let day = cells[i] {
                        if let onSelect, day <= .now {
                            Button { onSelect(day) } label: { cell(day) }.buttonStyle(.plain)
                        } else {
                            cell(day)
                        }
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
            HStack(spacing: 12) {
                legend(Color.orange, "채운 날")
                legend(Color.orange.opacity(0.25), "목표 미달")
                if !noted.isEmpty { legend(Color.accentColor, "메모") }
                if !slips.isEmpty { legend(Color.red.opacity(0.7), "한 날") }
                if !skipped.isEmpty { legend(Color.secondary, "건너뜀") }
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
            .foregroundStyle(status == .met ? Color.white : (day > .now || !isDue(day) ? Color.secondary : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                switch status {
                case .met: Circle().fill(Color.orange)
                case .partial: Circle().fill(Color.orange.opacity(0.25))
                case nil: Color.clear
                }
            }
            .overlay { if isToday { Circle().stroke(Color.accentColor, lineWidth: 1.5) } }
            .overlay(alignment: .bottom) {
                if noted.contains(day) { Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 3) }
            }
            .overlay {
                if slips.contains(day) { Circle().stroke(Color.red.opacity(0.7), lineWidth: 1.5) }
                if skipped.contains(day) { Circle().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])) }
            }
            .accessibilityLabel(Text(day, format: .dateTime.month().day()) + Text(status == .met ? ", 채움" : status == .partial ? ", 목표 미달" : "")
                                + Text(skipped.contains(day) ? ", 건너뜀" : "") + Text(noted.contains(day) ? ", 메모 있음" : ""))
    }

    /// 요일 지정일 때 정한 요일이 아닌 날은 흐리게 보인다.
    private func isDue(_ day: Date) -> Bool {
        guard case .weekdays(let set) = schedule, !set.isEmpty else { return true }
        return set.contains(calendar.component(.weekday, from: day))
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
    var schedule: HabitSchedule = .daily

    var body: some View {
        let current = progress?.phase
        Section {
            Text("새 행동이 저절로 나오기까지 평균 66일이 걸린다고 해요. 사람과 행동에 따라 18~254일로 차이가 크니, 66일은 기준일 뿐이에요. 그 과정을 세 단계로 나눠 보여 드려요.")
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
            Label(HabitCopy.rule(schedule), systemImage: "flame")
                .font(.footnote)
        } header: {
            Text("습관이 되는 과정")
        } footer: {
            let total = recordCount > 0 ? " 지금까지 \(recordCount)회 기록했어요." : ""
            if let progress, progress.streak > 0 {
                Text((progress.atRisk ? HabitCopy.risk(schedule, streak: progress.streak, weekDone: progress.weekDone) : "지금 \(progress.streak)일째 이어가고 있어요.") + total)
            } else {
                Text("오늘 목표를 채우면 1일째가 시작돼요." + total)
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
    /// 반응이 특정 물건 이야기면 누를 때 그 물건 상세(달력·메모·설정)를 연다.
    var onSelect: (KeyObject) -> Void = { _ in }

    var body: some View {
        let r = reaction
        Section {
            if let key = r.key {
                Button { onSelect(key) } label: { card(r, showsChevron: true) }
                    .tint(.primary)
                    .accessibilityHint("\(key.name) 상세 화면을 열어요")
            } else {
                card(r, showsChevron: false)
            }
        }
    }

    private func card(_ r: (mood: Moki, message: String, key: KeyObject?), showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(r.mood).resizable().scaledToFit().frame(width: 64, height: 64)
            Text(r.message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary) }
        }
    }

    private var reaction: (mood: Moki, message: String, key: KeyObject?) {
        // 끊기기 직전인 습관이 가장 먼저다. 이틀 연속만은 막는다.
        if let risky = items.filter(\.progress.atRisk).max(by: { $0.progress.streak < $1.progress.streak }) {
            return (.question, "\(risky.key.name), " + HabitCopy.risk(risky.key.schedule, streak: risky.progress.streak, weekDone: risky.progress.weekDone, quit: risky.key.isQuit), risky.key)
        }
        // 오늘 할 일만 본다. 쉬는 날·건너뛴 습관까지 넣으면 다 해도 "남은 것"이 있다고 말하게 된다.
        let todo = items.filter { TodayPlan.isTodo($0.key, $0.progress) }
        if !todo.isEmpty, todo.allSatisfy(\.progress.metToday) {
            return (.success, "오늘 할 일을 모두 했어요!", nil)
        }
        let goals = todo.filter { $0.progress.goal != nil }
        let metGoals = goals.filter { $0.progress.metToday }.count
        let activeToday = items.filter { $0.progress.today > 0 }.count
        if !goals.isEmpty, metGoals == goals.count {
            return (.success, "오늘 목표를 모두 채웠어요!", nil)
        }
        if !goals.isEmpty, metGoals > 0 || activeToday > 0 {
            // 개수는 바로 아래 "오늘 할 일" 머리글이 보여 준다. 기준이 다른 숫자를 또 쓰면 헷갈린다.
            return (.key, "오늘 시작했어요. 남은 것도 해 볼까요?", nil)
        }
        if activeToday > 0 {
            return (.reading, "오늘도 기록하고 있네요. 좋아요!", nil)
        }
        if let best = items.max(by: { $0.progress.streak < $1.progress.streak }),
           let phase = best.progress.phase {
            return (.peek, "\(best.key.name) \(best.progress.streak)일째, \(phase.label). \(phase.tip)", best.key)
        }
        return (.scan, "오늘 첫 물건을 스캔해 보세요. 작게 시작해도 충분해요.", nil)
    }
}
