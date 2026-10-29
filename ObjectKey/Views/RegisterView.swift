import SwiftData
import SwiftUI
import ObjectKeyCore

/// 새 물건에 능력 부여하기: 이름 → 동작 → 여러 각도 촬영.
struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private static let requiredShots = 3
    private static let maxShots = 6

    @State private var name = ""
    @State private var emoji = ""
    @State private var kind = "session"
    @State private var minutes = 5
    @State private var goal = 0
    @State private var shots: [CameraController.Frame] = []
    @State private var latest: CameraController.Frame?
    @State private var cameraAllowed: Bool?
    @State private var camera = CameraController()
    @FocusState private var focus: Field?

    private enum Field { case name, emoji }

    var body: some View {
        NavigationStack {
            Form {
                Section("물건") {
                    TextField("이름 (예: 내가 읽는 책)", text: $name)
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
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if kind == "countdown" {
                        Stepper("\(minutes)분", value: $minutes, in: 1...60)
                    }
                } header: {
                    Text("비추면 실행할 동작")
                } footer: {
                    Text("아이콘은 보기 위한 것이고, 실제로 무엇을 할지는 여기서 정합니다. 프리셋을 고르면 어울리는 동작이 자동으로 선택되며 바꿔도 됩니다.")
                }
                if kind != "countdown" {
                    Section {
                        GoalStepper(actionKind: kind, goal: $goal)
                    } header: {
                        Text("하루 목표 (선택)")
                    } footer: {
                        Text("목표를 채운 날이 이어지면 연속 일수가 올라갑니다. 나중에 목록에서 길게 눌러 바꿀 수 있어요.")
                    }
                }
                Section {
                    captureArea
                } header: {
                    Text("참조 사진 \(shots.count)/\(Self.requiredShots)+")
                } footer: {
                    Text("각도와 거리를 조금씩 바꿔 \(Self.requiredShots)장 이상 찍어 주세요. 비슷한 물건과 구별하는 데 도움이 됩니다. 사진은 기기 안에만 저장됩니다.")
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
            .task {
                let allowed = await CameraController.requestAccess()
                cameraAllowed = allowed
                if allowed { camera.start(includeThumbnail: true) { latest = $0 } }
            }
            .onDisappear { camera.stop() }
        }
    }

    @ViewBuilder
    private var captureArea: some View {
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

                Button {
                    focus = nil
                    if let latest { shots.append(latest) }
                } label: {
                    Label("촬영", systemImage: "camera.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(latest == nil || shots.count >= Self.maxShots)
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && shots.count >= Self.requiredShots
    }

    private var action: KeyAction {
        switch kind {
        case "countdown": return .countdown(minutes: minutes)
        case "counter": return .counter
        default: return .session
        }
    }

    private func save() {
        let vectors = shots.map(\.vector)
        let key = KeyObject(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji, action: action,
                            threshold: Calibration.suggestThreshold(for: vectors),
                            dailyGoal: kind == "countdown" ? 0 : goal)
        context.insert(key)
        key.shots = shots.map { ReferenceShot(vector: $0.vector, thumbnail: $0.thumbnail) }
        try? context.save()
        dismiss()
    }
}

struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(.question).resizable().scaledToFit().frame(height: 96)
            Text("카메라 권한이 꺼져 있어요").font(.headline)
            Text("물건을 등록하고 알아보려면 카메라가 필요합니다. 등록한 물건은 목록에서 눌러 바로 실행할 수도 있어요.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("설정에서 허용하기", destination: url)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}
