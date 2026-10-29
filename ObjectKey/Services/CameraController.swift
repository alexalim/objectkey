import AVFoundation
import SwiftUI
import ObjectKeyCore

/// 후면 카메라 세션. 프레임은 카메라 큐에서 특징값까지 계산한 뒤 메인 액터로 넘긴다.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// 처리한 프레임 하나. 가이드 안에 물체가 없으면 vector·region이 nil이다.
    struct Frame: Sendable {
        let vector: FeatureVector?
        let thumbnail: Data?
        /// 특징값을 뽑은 물체 영역(이미지 정규화 좌표, 좌하단 원점).
        let region: CGRect?
    }

    /// 세로로 돌린 버퍼의 가로/세로 비율. 미리보기 위에 가이드를 그릴 때 쓴다.
    static let bufferAspect: CGFloat = 9.0 / 16.0

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "objectkey.camera")
    private var configured = false
    private var lastProcessed = Date.distantPast
    /// 초당 처리 프레임 수 제한. 배터리와 발열을 고려한 값.
    private let minInterval: TimeInterval = 0.2

    // 아래 두 값은 카메라 큐에서만 읽고 쓴다.
    private var wantsThumbnail = false
    private var onFrame: (@MainActor (Frame) -> Void)?

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(includeThumbnail: Bool, onFrame: @escaping @MainActor (Frame) -> Void) {
        queue.async { [self] in
            self.wantsThumbnail = includeThumbnail
            self.onFrame = onFrame
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            onFrame = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        // 16:9로 고정해 bufferAspect와 맞춘다.
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        // 세로 화면 기준 버퍼로 받아 Vision orientation을 .up으로 고정한다.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard let onFrame, now.timeIntervalSince(lastProcessed) >= minInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = now
        let analysis = try? FeaturePrinter.analyze(pixelBuffer)
        let thumbnail = (wantsThumbnail ? analysis?.region : nil).flatMap { FeaturePrinter.thumbnail(from: pixelBuffer, region: $0) }
        let frame = Frame(vector: analysis?.vector, thumbnail: thumbnail, region: analysis?.region)
        Task { @MainActor in onFrame(frame) }
    }
}

/// AVCaptureSession 미리보기.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// 검출한 물체 영역을 aspect-fill 미리보기 위에 노란 테두리로 그린다. 모델이 실제로 보는 곳을 사용자에게 보여준다.
struct ObjectHighlight: View {
    /// 이미지 정규화 좌표(좌하단 원점). nil이면 아무것도 그리지 않는다.
    let region: CGRect?

    var body: some View {
        GeometryReader { geo in
            if let region {
                let shownWidth = max(geo.size.width, geo.size.height * CameraController.bufferAspect)
                let shownHeight = shownWidth / CameraController.bufferAspect
                let offsetX = (geo.size.width - shownWidth) / 2
                let offsetY = (geo.size.height - shownHeight) / 2
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: region.width * shownWidth, height: region.height * shownHeight)
                    .position(x: offsetX + region.midX * shownWidth, y: offsetY + (1 - region.midY) * shownHeight)
                    .animation(.easeOut(duration: 0.15), value: region)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 물체를 찾는 가운데 정사각형을 보여주는 가이드. FeaturePrinter.regionFraction과 맞춘다.
/// 미리보기는 버퍼를 aspect-fill로 채우므로, 화면에 실제로 그려지는 버퍼의 짧은 변을 기준으로 변 길이를 구한다.
struct ScanGuide: View {
    var body: some View {
        GeometryReader { geo in
            let side = FeaturePrinter.regionFraction * max(geo.size.width, geo.size.height * CameraController.bufferAspect)
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}
