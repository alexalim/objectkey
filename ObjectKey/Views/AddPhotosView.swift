import SwiftData
import SwiftUI
import ObjectKeyCore

/// 카메라 미리보기·찍은 사진·촬영 버튼. 등록 화면과 "사진 찍어 스캔 켜기"가 함께 쓴다.
struct ShotCaptureArea: View {
    let camera: CameraController
    let latest: CameraController.Frame?
    @Binding var shots: [CameraController.Frame]
    let maxShots: Int
    /// 촬영을 누를 때 부른다(등록 화면은 키보드를 내린다).
    var onShutter: () -> Void = {}

    var body: some View {
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
                        Self.thumbnail(shots[i].thumbnail)
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
                onShutter()
                if let latest, latest.vector != nil { shots.append(latest) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text("촬영")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(latest?.vector == nil || shots.count >= maxShots)
        }
    }

    static func thumbnail(_ data: Data?) -> some View {
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
}

/// 사진 없이 만든 습관에 나중에 사진을 붙여 스캔을 켠다. 3장을 찍으면 다음부터 물건을 비추기만 해도 열린다.
struct AddPhotosView: View {
    let key: KeyObject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var camera = CameraController()
    @State private var latest: CameraController.Frame?
    @State private var shots: [CameraController.Frame] = []
    @State private var cameraAllowed: Bool?

    static let requiredShots = 3
    private static let maxShots = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("\(key.name) 물건을 여러 각도로 \(Self.requiredShots)장 찍어 주세요. 다음부터는 물건을 비추기만 해도 바로 열려요.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    switch cameraAllowed {
                    case .none:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    case .some(false):
                        CameraDeniedView()
                    case .some(true):
                        ShotCaptureArea(camera: camera, latest: latest, shots: $shots, maxShots: Self.maxShots)
                    }
                }
                .padding()
            }
            .navigationTitle("사진 찍어 스캔 켜기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(shots.count >= Self.requiredShots ? "저장" : "\(shots.count)/\(Self.requiredShots)") { save() }
                        .disabled(shots.count < Self.requiredShots)
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

    private func save() {
        let vectors = shots.compactMap(\.vector)
        key.shots = shots.compactMap { shot in shot.vector.map { ReferenceShot(vector: $0, thumbnail: shot.thumbnail) } }
        key.threshold = Calibration.suggestThreshold(for: vectors)
        if context.saveOrReport() { dismiss() }
    }
}
