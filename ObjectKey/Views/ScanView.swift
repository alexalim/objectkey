import SwiftData
import SwiftUI
import ObjectKeyCore

/// 물건을 비추면 연속 프레임에서 같은 물건이 확인될 때만 그 물건의 실행 화면을 연다. 기록은 실행 화면에서 [완료]로.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]

    @State private var camera = CameraController()
    @State private var cameraAllowed: Bool?
    @State private var filter = StabilityFilter(requiredStreak: 3)
    @State private var hint = "네모 칸 안에 물건을 맞춰 주세요"
    @State private var paused = false
    @State private var choices: [KeyObject] = []
    /// 직접 선택 창에서 고른 물건. 창이 다 닫힌 뒤에 실행 화면을 연다(시트가 겹치면 뜨지 않는다).
    @State private var manualPick: KeyObject?
    /// 고르는 창이 "어느 물건"이 아니라 "이 물건의 어느 습관"을 묻는 중인지.
    @State private var pickingHabit = false
    /// 물건을 고른 뒤 습관 고르는 창을 다시 띄우는 중. 그사이 스캔이 다시 돌지 않게 한다.
    @State private var reopening = false
    @State private var showManual = false
    @State private var mood: Moki = .scan
    @State private var lastSeen = Date()
    @State private var objectRegion: CGRect?
    /// 알아본 물건. 바로 기록하지 않고 실행 화면을 연다.
    @State private var runKey: KeyObject?

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
                ObjectHighlight(region: objectRegion).ignoresSafeArea()
            }
            VStack {
                HStack {
                    // 카메라 위라 잘 안 보이고 작았다. 어두운 원 배경과 44pt 이상 누를 영역을 준다.
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3.bold())
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.45), in: Circle())
                    }
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
                // 큰 화면에서는 위쪽 X에 손이 잘 닿지 않아 아래에도 닫기를 둔다.
                HStack(spacing: 12) {
                    Button("닫기") { dismiss() }
                    Button("직접 선택") { showManual = true }
                }
                .buttonStyle(.bordered).tint(.white).controlSize(.large)
                .padding(.bottom, 24)
            }
        }
        .task {
            let allowed = await CameraController.requestAccess()
            cameraAllowed = allowed
            if allowed { camera.start(includeThumbnail: false) { process($0) } }
            else { showManual = true }
        }
        .onDisappear { camera.stop() }
        .confirmationDialog(pickingHabit ? "어떤 습관을 할까요?" : "어떤 물건인가요?",
                            isPresented: Binding(get: { !choices.isEmpty }, set: {
                                if !$0 { choices = []; if runKey == nil && !reopening { paused = false } }
                            }),
                            titleVisibility: .visible) {
            ForEach(choices) { key in
                Button(key.name) { picked(key) }
            }
        } message: {
            Text(pickingHabit ? "이 물건에 연결한 습관이 여러 개예요." : "비슷한 물건이 여러 개예요. 고를 때까지 기다릴게요.")
        }
        .sheet(isPresented: $showManual, onDismiss: {
            // 직접 선택은 습관 목록에서 고르므로 바로 실행 화면을 연다.
            if let key = manualPick { manualPick = nil; runKey = key } else { paused = false }
        }) { manualPicker }
        // 실행 화면을 닫으면(완료든 나중에든) 스캔도 끝내고 오늘 화면으로 돌아간다.
        .sheet(item: $runKey, onDismiss: { dismiss() }) { HabitRunView(key: $0) }
    }

    private func process(_ frame: CameraController.Frame) {
        guard !paused, choices.isEmpty, runKey == nil else { return }
        objectRegion = frame.region
        // 가이드 안에 물체가 없으면 비교조차 하지 않는다. 빈 책상에서 실행되는 일을 막는다.
        guard let vector = frame.vector else {
            _ = filter.feed(.noMatch)
            if Date.now.timeIntervalSince(lastSeen) > 4 {
                hint = "네모 칸 안에 물건이 안 보여요. 조금 더 가까이 대 주세요"
                mood = .question
            }
            return
        }
        let registered = keys.map(\.registered)
        let outcome = matcher.evaluate(vector, against: registered)
        if case .match(let candidate) = outcome, let key = keys.first(where: { $0.id == candidate.keyID }) {
            hint = "\(key.name) 확인 중…"
            mood = .key
            lastSeen = .now
        } else if Date.now.timeIntervalSince(lastSeen) > 4 {
            hint = "등록한 물건을 찾지 못했어요. 가까이 대거나 직접 골라 주세요"
            mood = .question
        } else {
            hint = "네모 칸 안에 물건을 맞춰 주세요"
            mood = .scan
        }
        guard let confirmed = filter.feed(outcome) else { return }
        paused = true
        switch confirmed {
        case .match(let candidate):
            if let key = keys.first(where: { $0.id == candidate.keyID }) { open(key) } else { paused = false }
        case .ambiguous(let candidates):
            choices = keys.filter { key in candidates.contains { $0.keyID == key.id } }
        case .noMatch:
            paused = false
        }
    }

    /// 알아본 물건을 연다. 그 물건에 습관이 여럿이면 어느 습관인지 먼저 묻는다.
    private func open(_ key: KeyObject) {
        reopening = false
        let members = key.objectMembers(in: keys)
        if members.count > 1 {
            pickingHabit = true
            choices = members
        } else {
            choices = []
            runKey = key
        }
    }

    private func picked(_ key: KeyObject) {
        if pickingHabit {
            pickingHabit = false
            runKey = key
            return
        }
        // 물건을 골랐다. 창이 닫힌 뒤에 습관 고르는 창(또는 실행 화면)을 연다.
        reopening = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            open(key)
        }
    }

    private var manualPicker: some View {
        NavigationStack {
            List(keys) { key in
                Button {
                    manualPick = key
                    showManual = false
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
