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
enum FeaturePrinter {
    /// 짧은 변의 이 비율만큼 가운데 정사각형만 본다. 배경 영향을 줄이기 위해서다. ScanGuide와 같은 값을 쓴다.
    static let regionFraction: CGFloat = 0.6

    /// 버퍼 크기에 맞춘 정규화 ROI(좌하단 원점). 정사각형이라 Vision의 centerCrop으로 더 잘려 나가는 부분이 없다.
    static func regionOfInterest(width: Int, height: Int) -> CGRect {
        let side = regionFraction * CGFloat(min(width, height))
        let w = side / CGFloat(width), h = side / CGFloat(height)
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    static func vector(from pixelBuffer: CVPixelBuffer) throws -> FeatureVector {
        let roi = regionOfInterest(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let request = VNGenerateImageFeaturePrintRequest()
        // 리비전을 고정하지 않으면 SDK가 바뀔 때 저장된 벡터와 비교가 끊겨 등록한 물건이 전부 인식되지 않는다.
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .centerCrop
        request.regionOfInterest = roi
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        guard let observation = request.results?.first else { throw FeaturePrinterError.noObservation }
        return FeatureVector(values: try floats(of: observation), revision: request.revision)
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

    /// 등록 화면에 보여줄 작은 썸네일. 특징값을 뽑은 정사각형과 같은 영역을 자른다.
    static func thumbnail(from pixelBuffer: CVPixelBuffer, maxSide: CGFloat = 240) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        let roi = regionOfInterest(width: Int(extent.width), height: Int(extent.height))
        // Vision 좌표(좌하단 원점)와 CIImage 좌표가 같으므로 그대로 쓴다.
        let crop = CGRect(x: extent.minX + extent.width * roi.minX,
                          y: extent.minY + extent.height * roi.minY,
                          width: extent.width * roi.width,
                          height: extent.height * roi.height)
        let scale = maxSide / max(crop.width, crop.height)
        let output = image.cropped(to: crop).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}
