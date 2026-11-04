import SwiftData
import SwiftUI
import ObjectKeyCore

/// 새 물건에 능력 부여하기: 이름 → 동작 → 여러 각도 촬영.
struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var existing: [KeyObject]

    private static let requiredShots = 3
    private static let maxShots = 6

    @State private var name = ""
    @State private var emoji = ""
    @State private var kind = "session"
    @State private var minutes = 5
    @State private var goal = 0
    @State private var cue = ""
    @State private var reminderMinute = -1
    @State private var schedule: HabitSchedule = .daily
    @State private var attendStart = 21 * 60
    @State private var attendMinutes = 90
    @State private var tags: [String] = []
    @State private var measureStep = 0
    @State private var measureUnit = ""
    @State private var healthMetric = ""
    @State private var healthTarget = 0
    @State private var shots: [CameraController.Frame] = []
    @State private var latest: CameraController.Frame?
    @State private var cameraAllowed: Bool?
    /// 사진은 선택이다. 누를 때만 카메라를 켜서, 사진 없이 쓰는 사람에게 권한 창을 띄우지 않는다.
    @State private var wantsPhotos = false
    @State private var camera = CameraController()
    @State private var duplicateOf: KeyObject?
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    private enum Field { case name, emoji, cue }

    /// 저장이 끝나면 부른다. "MOKI에게 말하기"에서 열었을 때 그 창까지 닫고 홈으로 가기 위해서다.
    var onSaved: (() -> Void)?

    init(draft: RegisterDraft? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        // "MOKI에게 말하기"로 해석한 값을 미리 채운다. 사진은 원하면 직접 찍는다.
        guard let d = draft else { return }
        _name = State(initialValue: d.name)
        _emoji = State(initialValue: d.emoji)
        _kind = State(initialValue: d.kind)
        _minutes = State(initialValue: d.countdownMinutes)
        _goal = State(initialValue: d.goal)
        _cue = State(initialValue: d.cue)
        _reminderMinute = State(initialValue: d.reminderMinute)
        _schedule = State(initialValue: d.schedule)
        _attendStart = State(initialValue: d.attendStart)
        _attendMinutes = State(initialValue: d.attendMinutes)
        _tags = State(initialValue: d.tags)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("물건") {
                    TextField("이름 (예: 읽는 책)", text: $name)
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Moki.activities, id: \.self) { moki in
                                Button { emoji = moki.assetName; focus = nil } label: {
                                    VStack(spacing: 2) {
                                        Image(moki).resizable().scaledToFit().frame(width: 56, height: 56)
                                        Text(moki.label).font(.caption2)
                                    }
                                    .padding(4)
                                    .background(emoji == moki.assetName ? Color.accentColor.opacity(0.15) : .clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(moki.label) 캐릭터")
                            }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(EmojiPreset.all) { preset in
                            Button {
                                emoji = preset.emoji
                                kind = preset.suggestedKind
                                // 태그를 아직 안 골랐으면 아이콘에 어울리는 태그를 하나 제안한다.
                                if tags.isEmpty, let tag = preset.suggestedTag { tags = [tag] }
                                focus = nil
                            } label: {
                                VStack(spacing: 2) {
                                    Text(preset.emoji).font(.title2)
                                    Text(preset.label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(emoji == preset.emoji ? Color.accentColor.opacity(0.15) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.label)
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("직접 입력 (이모지 하나)", text: Binding(
                        get: { emoji.hasPrefix("moki-") ? "" : emoji },
                        set: { emoji = String($0.prefix(1)) }))
                        .focused($focus, equals: .emoji)
                }
                Section {
                    Picker("동작", selection: $kind) {
                        Text("시간 기록 시작·종료").tag("session")
                        Text("휴식 타이머").tag("countdown")
                        Text("횟수 +1").tag("counter")
                        Text("정해진 시간 참석 (수업·레슨)").tag("attend")
                        Text("끊기 (안 한 날이 성공)").tag("quit")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if kind == "countdown" {
                        Stepper("\(minutes)분", value: $minutes, in: 1...60)
                    }
                    if kind == "attend" {
                        AttendEditor(startMinute: $attendStart, minutes: $attendMinutes)
                    }
                    if kind == "counter" {
                        MeasureEditor(step: $measureStep, unit: $measureUnit)
                    }
                } header: {
                    Text("스캔하면 실행할 동작")
                } footer: {
                    Text(kind == "attend" ? HabitCopy.attendFooter
                         : kind == "quit" ? HabitCopy.quitFooter
                         : kind == "counter" ? HabitCopy.measureFooter
                         : "아이콘을 고르면 어울리는 동작이 먼저 골라져요. 원하는 동작으로 바꿔도 돼요.")
                }
                if kind != "countdown" {
                    Section {
                        // 끊기는 매일 지키는 것이라 일정·목표·알림이 필요 없다.
                        if kind != "quit" { ScheduleEditor(schedule: $schedule) }
                        if kind == "counter" || kind == "session" { HealthLinkEditor(metric: $healthMetric, target: $healthTarget) }
                        TagPicker(tags: $tags)
                        if kind != "attend" && kind != "quit" {
                            GoalStepper(actionKind: kind, goal: $goal, measureStep: measureUnit.isEmpty ? 0 : max(measureStep, 1),
                                        measureUnit: measureUnit)
                        }
                        if kind != "quit" {
                            TextField(HabitCopy.cuePlaceholder, text: $cue)
                                .focused($focus, equals: .cue)
                                .submitLabel(.done)
                            ReminderPicker(minute: $reminderMinute, defaultMinute: kind == "attend" ? max(0, attendStart - 30) : 9 * 60)
                        }
                    } header: {
                        Text("습관 (선택)")
                    } footer: {
                        Text(HabitCopy.goalFooter + " 나중에 홈에서 오른쪽으로 밀어 바꿀 수 있어요.")
                    }
                }
                Section {
                    captureArea
                } header: {
                    Text(shots.isEmpty ? "물건 사진 (선택)" : "물건 사진 \(shots.count)장 (선택)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if wantsPhotos {
                            Text("노란 상자가 물건을 감싸면 각도와 거리를 조금씩 바꿔 \(Self.requiredShots)장 이상 찍어 주세요. 사진은 이 기기에만 저장돼요.")
                        }
                        Text(photoNote).foregroundStyle(shots.isEmpty || shots.count >= Self.requiredShots ? Color.secondary : Color.orange)
                        if let saveHint { Text(saveHint).foregroundStyle(.orange) }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("새 물건 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save).disabled(!canSave)
                }
                // 이모지 키보드에는 Return 키가 없어 내릴 방법이 따로 필요하다.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focus = nil }
                }
            }
            .onDisappear { camera.stop() }
            .alert("저장하지 못했어요", isPresented: $saveFailed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("잠시 뒤 다시 저장해 주세요. 계속 안 되면 이 화면을 피드백으로 보내 주세요.")
            }
            .alert("이미 등록한 물건과 비슷해요",
                   isPresented: Binding(get: { duplicateOf != nil }, set: { if !$0 { duplicateOf = nil } }),
                   presenting: duplicateOf) { _ in
                Button("그래도 등록", action: commit)
                Button("취소", role: .cancel) {}
            } message: { key in
                Text("'\(key.name)'하고 비슷해 보여요. 둘 다 두면 스캔할 때마다 어느 쪽인지 골라야 해요.")
            }
        }
    }

    private func startCamera() async {
        wantsPhotos = true
        focus = nil
        let allowed = await CameraController.requestAccess()
        cameraAllowed = allowed
        if allowed { camera.start(includeThumbnail: true) { latest = $0 } }
    }

    /// 사진이 몇 장인지에 따라 무엇이 되고 안 되는지 알려 준다. 저장을 막지는 않는다.
    private var photoNote: String {
        switch shots.count {
        case 0: return "사진 없이도 저장할 수 있어요. 대신 스캔으로는 알아보지 못하니 상세 화면 버튼·위젯·Siri·✨로 기록해요."
        case 1..<Self.requiredShots: return "\(Self.requiredShots - shots.count)장 더 찍으면 스캔으로 알아봐요. 지금 저장해도 돼요."
        default: return "스캔하면 알아볼 수 있어요."
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if !wantsPhotos {
            Button {
                Task { await startCamera() }
            } label: {
                Label("카메라로 사진 찍기", systemImage: "camera").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            cameraArea
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch cameraAllowed {
        case .none:
            ProgressView().frame(maxWidth: .infinity)
        case .some(false):
            CameraDeniedView()
        case .some(true):
            VStack(spacing: 12) {
                ZStack {
                    CameraPreview(session: camera.session)
                    ScanGuide()
                    ObjectHighlight(region: latest?.region)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                ScrollView(.horizontal) {
                    HStack {
                        ForEach(shots.indices, id: \.self) { i in
                            thumbnail(shots[i].thumbnail)
                                .overlay(alignment: .topTrailing) {
                                    Button { shots.remove(at: i) } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain).foregroundStyle(.white, .black.opacity(0.6))
                                }
                        }
                    }
                }

                if latest?.vector == nil {
                    Text("네모 칸 안에서 물건을 찾는 중… 노란 상자가 물건을 감싸면 촬영할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button {
                    focus = nil
                    if let latest, latest.vector != nil { shots.append(latest) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text("촬영")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(latest?.vector == nil || shots.count >= Self.maxShots)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
    }

    private func thumbnail(_ data: Data?) -> some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var canSave: Bool { saveHint == nil }

    /// 저장 버튼이 왜 꺼져 있는지. 다 채워지면 nil.
    private var saveHint: String? {
        var missing: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("이름을 입력") }
        return missing.isEmpty ? nil : "저장하려면 " + missing.joined(separator: "하고, ") + "해 주세요."
    }

    private var action: KeyAction {
        switch kind {
        case "countdown": return .countdown(minutes: minutes)
        case "counter", "quit": return .counter
        case "attend": return .attend(startMinute: attendStart, minutes: attendMinutes)
        default: return .session
        }
    }

    /// 같은 물건을 또 등록하면 비출 때마다 골라야 하므로 막지는 않고 알려만 준다.
    private func save() {
        if let similar = closestExisting() { duplicateOf = similar } else { commit() }
    }

    /// 새 사진이 기존 물건의 임계값 안에 들어오면 그중 가장 가까운 물건.
    private func closestExisting() -> KeyObject? {
        let vectors = shots.compactMap(\.vector)
        return existing.compactMap { key -> (KeyObject, Float)? in
            let references = key.shots.compactMap(\.vector)
            let nearest = vectors.flatMap { v in references.compactMap { v.distance(to: $0) } }.min()
            guard let nearest, nearest <= Calibration.effectiveThreshold(key.threshold) else { return nil }
            return (key, nearest)
        }
        .min { $0.1 < $1.1 }?.0
    }

    private func commit() {
        let vectors = shots.compactMap(\.vector)
        let key = KeyObject(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji, action: action,
                            threshold: Calibration.suggestThreshold(for: vectors),
                            dailyGoal: kind == "countdown" || kind == "attend" || kind == "quit" ? 0 : goal)
        if kind == "quit" { key.isQuit = true }
        if kind == "counter" || kind == "session" {
            key.healthMetric = healthMetric
            key.healthTarget = healthTarget
        }
        if kind == "counter", !measureUnit.trimmingCharacters(in: .whitespaces).isEmpty {
            key.measureStep = max(measureStep, 1)
            key.measureUnit = measureUnit.trimmingCharacters(in: .whitespaces)
        }
        if kind != "countdown" {
            key.cue = cue.trimmingCharacters(in: .whitespaces)
            key.reminderMinute = reminderMinute
            key.schedule = schedule
            key.tags = tags
        }
        context.insert(key)
        // 미리 채운 알림은 권한 창을 거치지 않았을 수 있다. 저장할 때 한 번 묻는다.
        if key.reminderMinute >= 0 { Task { _ = await HabitReminders.requestPermission() } }
        key.shots = shots.compactMap { shot in shot.vector.map { ReferenceShot(vector: $0, thumbnail: shot.thumbnail) } }
        do {
            try context.save()
        } catch {
            // 조용히 실패하면 "등록했는데 없다"가 된다. 알리고 화면에 남는다.
            context.delete(key)
            saveFailed = true
            return
        }
        onSaved?()
        dismiss()
    }
}

struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(.question).resizable().scaledToFit().frame(height: 96)
            Text("카메라 권한이 꺼져 있어요").font(.headline)
            Text("스캔으로 기록하려면 카메라가 필요해요. 카메라 없이도 물건을 눌러 상세 화면에서 기록할 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("설정에서 허용하기", destination: url)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}
