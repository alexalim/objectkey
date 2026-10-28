import AVFoundation
import SwiftUI
import ObjectKeyCore

/// 후면 카메라 세션. 프레임은 카메라 큐에서 특징값까지 계산한 뒤 메인 액터로 넘긴다.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Frame: Sendable {
        let vector: FeatureVector
        let thumbnail: Data?
    }

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
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

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
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let vector = try? FeaturePrinter.vector(from: pixelBuffer) else { return }
        lastProcessed = now
        let frame = Frame(vector: vector, thumbnail: wantsThumbnail ? FeaturePrinter.thumbnail(from: pixelBuffer) : nil)
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

/// 특징값을 뽑는 중앙 영역을 보여주는 가이드. FeaturePrinter.regionOfInterest와 맞춘다.
struct ScanGuide: View {
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .frame(width: geo.size.width * 0.6, height: geo.size.height * 0.6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}
