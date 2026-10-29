import SwiftData
import SwiftUI
import ObjectKeyCore

/// 물건을 비추면 연속 프레임에서 같은 물건이 확인될 때만 실행한다.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]

    @State private var camera = CameraController()
    @State private var cameraAllowed: Bool?
    @State private var filter = StabilityFilter(requiredStreak: 3)
    @State private var hint = "가이드 안에 물건을 비춰 주세요"
    @State private var paused = false
    @State private var choices: [KeyObject] = []
    @State private var pending: PendingSwitch?
    @State private var showManual = false
    @State private var mood: Moki = .scan
    @State private var lastSeen = Date()

    private let matcher = ObjectMatcher()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch cameraAllowed {
            case .none:
                ProgressView().tint(.white)
            case .some(false):
                CameraDeniedView().foregroundStyle(.white).padding()
            case .some(true):
                CameraPreview(session: camera.session).ignoresSafeArea()
                ScanGuide().ignoresSafeArea()
            }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.title2.bold()) }
                        .accessibilityLabel("닫기")
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding()
                Spacer()
                Image(mood).resizable().scaledToFit().frame(height: 110)
                    .animation(.spring, value: mood)
                Text(hint)
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                Button("직접 선택") { showManual = true }
                    .buttonStyle(.bordered).tint(.white)
                    .padding(.bottom, 24)
            }
        }
        .task {
            let allowed = await CameraController.requestAccess()
            cameraAllowed = allowed
            if allowed { camera.start(includeThumbnail: false) { process($0.vector) } }
            else { showManual = true }
        }
        .onDisappear { camera.stop() }
        .confirmationDialog("어떤 물건인가요?", isPresented: Binding(get: { !choices.isEmpty }, set: { if !$0 { choices = []; paused = false } }),
                            titleVisibility: .visible) {
            ForEach(choices) { key in
                Button(key.name) { run(store.activate(key, keys: keys, context: context)) }
            }
        } message: {
            Text("비슷한 물건이 여러 개 보여요. 실행하지 않고 기다리는 중입니다.")
        }
        .switchConfirmation($pending, keys: keys) { dismiss() }
        .sheet(isPresented: $showManual, onDismiss: { paused = false }) { manualPicker }
    }

    private func process(_ vector: FeatureVector) {
        guard !paused, choices.isEmpty, pending == nil else { return }
        let outcome = matcher.evaluate(vector, against: keys.map(\.registered))
        if case .match(let candidate) = outcome, let key = keys.first(where: { $0.id == candidate.keyID }) {
            hint = "\(key.name) 확인 중…"
            mood = .key
            lastSeen = .now
        } else if Date.now.timeIntervalSince(lastSeen) > 4 {
            hint = "등록한 물건이 안 보여요. 가까이 비추거나 직접 선택해 주세요"
            mood = .question
        } else {
            hint = "가이드 안에 물건을 비춰 주세요"
            mood = .scan
        }
        guard let confirmed = filter.feed(outcome) else { return }
        paused = true
        run(store.handle(confirmed, keys: keys, context: context))
    }

    private func run(_ resolution: ScanResolution) {
        switch resolution {
        case .executed:
            dismiss()
        case .needsConfirmation(let p):
            pending = p
        case .needsChoice(let ids):
            choices = keys.filter { ids.contains($0.id) }
        case .notRecognized:
            paused = false
        }
    }

    private var manualPicker: some View {
        NavigationStack {
            List(keys) { key in
                Button {
                    showManual = false
                    run(store.activate(key, keys: keys, context: context))
                } label: { KeyRow(key: key, active: store.state.activeKeyID == key.id) }
                    .tint(.primary)
            }
            .navigationTitle("직접 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showManual = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
