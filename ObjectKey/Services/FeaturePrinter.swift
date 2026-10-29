import CoreImage
import CoreVideo
import UIKit
import Vision
import ObjectKeyCore

enum FeaturePrinterError: Error {
    case noObservation
    case unsupportedElementType
}

/// Vision feature print 추출. 등록과 스캔이 반드시 같은 설정을 쓰도록 여기 한 곳에만 둔다.
///
/// feature print는 장면 전체의 유사도를 재는 지표라 배경이 많이 들어오면 물건을 구분하지 못한다.
/// 그래서 먼저 가이드 안에서 가장 눈에 띄는 물체 상자를 찾고, 그 상자만 잘라 특징값을 뽑는다.
enum FeaturePrinter {
    /// 짧은 변의 이 비율만큼 가운데 정사각형 안에서만 물체를 찾는다. ScanGuide와 같은 값을 쓴다.
    static let regionFraction: CGFloat = 0.6
    /// 물체 상자 주변에 두는 여유 비율.
    private static let boxPadding: CGFloat = 1.2
    /// 가이드 면적 대비 이보다 작은 상자는 물체로 보지 않는다.
    private static let minimumBoxArea: CGFloat = 0.04

    struct Analysis {
        let vector: FeatureVector
        /// 특징값을 뽑은 영역(이미지 정규화 좌표, 좌하단 원점).
        let region: CGRect
    }

    /// 버퍼 크기에 맞춘 정규화 가이드 영역(좌하단 원점). 정사각형이라 centerCrop으로 더 잘리는 부분이 없다.
    static func regionOfInterest(width: Int, height: Int) -> CGRect {
        let side = regionFraction * CGFloat(min(width, height))
        let w = side / CGFloat(width), h = side / CGFloat(height)
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    /// 가이드 안에서 물체를 찾아 특징값을 뽑는다. 물체가 없으면 nil — 스캔은 미인식, 등록은 촬영 불가로 다룬다.
    static func analyze(_ pixelBuffer: CVPixelBuffer) throws -> Analysis? {
        let guide = regionOfInterest(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard let region = salientObjectRegion(in: guide, handler: handler) else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        // 리비전을 고정하지 않으면 SDK가 바뀔 때 저장된 벡터와 비교가 끊겨 등록한 물건이 전부 인식되지 않는다.
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .centerCrop
        request.regionOfInterest = region
        try handler.perform([request])
        guard let observation = request.results?.first else { throw FeaturePrinterError.noObservation }
        return Analysis(vector: FeatureVector(values: try floats(of: observation), revision: request.revision), region: region)
    }

    /// 이미지 전체에서 물체 상자들을 찾은 뒤, 중심이 가이드 안에 있는 것 중 가장 큰 상자.
    /// 전체 이미지에 돌리는 이유: ROI를 주면 결과 좌표 기준이 헷갈리므로 처음부터 이미지 좌표로 받는다.
    private static func salientObjectRegion(in guide: CGRect, handler: VNImageRequestHandler) -> CGRect? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        guard (try? handler.perform([request])) != nil,
              let objects = request.results?.first?.salientObjects else { return nil }
        let inside = objects.map(\.boundingBox).filter { guide.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        guard let box = inside.max(by: { $0.width * $0.height < $1.width * $1.height }),
              box.width * box.height >= guide.width * guide.height * minimumBoxArea else { return nil }

        // 여유를 두고, 픽셀 기준 정사각형으로 만든 뒤 이미지 안으로 자른다.
        // 정규화 좌표에서는 가로·세로 비율이 다르므로 가이드(픽셀 정사각형)의 비율을 빌려 쓴다.
        let sideX = min(1, max(box.width, box.height * guide.width / guide.height) * boxPadding)
        let sideY = sideX * guide.height / guide.width
        let square = CGRect(x: box.midX - sideX / 2, y: box.midY - sideY / 2, width: sideX, height: sideY)
        return square.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func floats(of observation: VNFeaturePrintObservation) throws -> [Float] {
        let data = observation.data
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
        default:
            throw FeaturePrinterError.unsupportedElementType
        }
    }

    private static let ciContext = CIContext()

    /// 등록 화면에 보여줄 작은 썸네일. 특징값을 뽑은 영역과 같은 곳을 자른다.
    static func thumbnail(from pixelBuffer: CVPixelBuffer, region: CGRect, maxSide: CGFloat = 240) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        // Vision 좌표(좌하단 원점)와 CIImage 좌표가 같으므로 그대로 쓴다.
        let crop = CGRect(x: extent.minX + extent.width * region.minX,
                          y: extent.minY + extent.height * region.minY,
                          width: extent.width * region.width,
                          height: extent.height * region.height)
        let scale = maxSide / max(crop.width, crop.height)
        let output = image.cropped(to: crop).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}
