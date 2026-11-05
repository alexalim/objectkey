import SwiftData
import SwiftUI
import ObjectKeyCore

/// 인식 점검. 물건을 비추면서 "이건 영양제", "이건 다른 물건"을 고르면 거리값이 쌓이고,
/// 물건마다 권장 기준값을 계산해 적용하거나 결과를 공유할 수 있다. 기준값을 실제 데이터로 정하기 위한 도구다.
struct CalibrationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KeyObject.createdAt) private var allKeys: [KeyObject]

    @State private var camera = CameraController()
    @State private var cameraAllowed: Bool?
    /// 지금 비추는 물건. nil이면 "다른 물건".
    @State private var target: UUID?
    @State private var recording = false
    @State private var samples: [Sample] = []
    @State private var live: [Candidate] = []
    @State private var lastSampleAt = Date.distantPast
    @State private var applied: String?

    private let matcher = ObjectMatcher()

    struct Sample {
        let label: UUID?
        let distances: [UUID: Float]
    }

    private var keys: [KeyObject] { allKeys.filter { !$0.shots.isEmpty } }

    var body: some View {
        List {
            Section {
                if cameraAllowed == true {
                    ZStack {
                        CameraPreview(session: camera.session)
                        ScanGuide()
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } else if cameraAllowed == false {
                    CameraDeniedView()
                }
                Picker("지금 비추는 것", selection: $target) {
                    ForEach(keys) { Text($0.name).tag(Optional($0.id)) }
                    Text("다른 물건 (예: 키보드)").tag(UUID?.none)
                }
                Toggle(recording ? "기록 중… (\(samples.count)개)" : "기록 시작", isOn: $recording)
                Text(live.prefix(3).map { c in "\(name(c.keyID)) \(String(format: "%.2f", c.distance))" }.joined(separator: " · "))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } header: {
                Text("비추면서 기록")
            } footer: {
                Text("물건마다 각도·거리·조명을 바꿔 가며 10초씩, '다른 물건'으로 헷갈렸던 물건(키보드 등)도 10초씩 기록해 주세요.")
            }

            if !samples.isEmpty {
                Section {
                    ForEach(keys) { key in
                        resultRow(key)
                    }
                } header: {
                    Text("물건별 결과")
                } footer: {
                    Text("숫자가 작을수록 같은 물건으로 봐요. '갈림'이면 기준값으로 두 무리를 나눌 수 있고, '겹침'이면 잘못 알아보지 않는 쪽으로 권해요.")
                }
                Section {
                    ShareLink(item: report(), preview: SharePreview("MOKI 인식 점검 결과")) {
                        Label("결과 보내기", systemImage: "square.and.arrow.up")
                    }
                    Button("기록 지우기", role: .destructive) { samples = [] }
                }
            }
            if let applied {
                Section { Label(applied, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("인식 점검")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let allowed = await CameraController.requestAccess()
            cameraAllowed = allowed
            if allowed { camera.start(includeThumbnail: false) { process($0) } }
        }
        .onDisappear { camera.stop() }
        .onAppear { if target == nil { target = keys.first?.id } }
    }

    private func process(_ frame: CameraController.Frame) {
        guard let vector = frame.vector else { live = []; return }
        let candidates = matcher.distances(vector, against: keys.map(\.registered))
        live = candidates
        // 너무 비슷한 프레임이 쌓이지 않게 0.3초마다 하나씩.
        guard recording, Date.now.timeIntervalSince(lastSampleAt) > 0.3 else { return }
        lastSampleAt = .now
        samples.append(Sample(label: target, distances: Dictionary(uniqueKeysWithValues: candidates.map { ($0.keyID, $0.distance) })))
    }

    private func split(_ key: KeyObject) -> (pos: [Float], neg: [Float]) {
        var pos: [Float] = [], neg: [Float] = []
        for s in samples {
            guard let d = s.distances[key.id] else { continue }
            if s.label == key.id { pos.append(d) } else { neg.append(d) }
        }
        return (pos, neg)
    }

    @ViewBuilder
    private func resultRow(_ key: KeyObject) -> some View {
        let (pos, neg) = split(key)
        let current = Calibration.effectiveThreshold(key.threshold)
        VStack(alignment: .leading, spacing: 4) {
            Text(key.name).font(.headline)
            Text("같은 물건 \(pos.count)개 · 최대 \(fmt(pos.max())) / 다른 물건 \(neg.count)개 · 최소 \(fmt(neg.min()))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let r = Calibration.recommend(positives: pos, negatives: neg) {
                let value = min(r.threshold, Calibration.maximumThreshold)
                HStack {
                    Text("지금 \(fmt(current)) → 권장 \(fmt(value)) · \(r.separable ? "갈림" : "겹침")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(r.separable ? Color.primary : Color.orange)
                    Spacer()
                    Button("적용") {
                        key.threshold = value
                        context.saveOrReport()
                        applied = "\(key.name) 기준을 \(fmt(value))로 바꿨어요."
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("같은 물건과 다른 물건을 둘 다 기록해야 권장값이 나와요.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func name(_ id: UUID) -> String { allKeys.first { $0.id == id }?.name ?? "?" }
    private func fmt(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "–" }

    /// 공유용 결과. 물건 이름과 거리만 담고 사진은 담지 않는다.
    private func report() -> String {
        var lines = ["MOKI 인식 점검 \(Date.now.formatted(.iso8601))", "샘플 \(samples.count)개"]
        for key in keys {
            let (pos, neg) = split(key)
            let rec = Calibration.recommend(positives: pos, negatives: neg)
            lines.append("[\(key.name)] 사진 \(key.shots.count)장, 지금 기준 \(fmt(Calibration.effectiveThreshold(key.threshold)))"
                + ", 권장 \(fmt(rec?.threshold)) \(rec.map { $0.separable ? "갈림" : "겹침" } ?? "")")
            lines.append("  같은 물건: " + pos.map { fmt($0) }.joined(separator: " "))
            lines.append("  다른 물건: " + neg.map { fmt($0) }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
