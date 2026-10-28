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
    /// 화면의 가이드 사각형과 같은 중앙 영역만 본다. 배경 영향을 줄이기 위해서다.
    static let regionOfInterest = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    static func vector(from pixelBuffer: CVPixelBuffer) throws -> FeatureVector {
        try run(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up))
    }

    private static func run(_ handler: VNImageRequestHandler) throws -> FeatureVector {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .centerCrop
        request.regionOfInterest = regionOfInterest
        try handler.perform([request])
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

    /// 등록 화면·목록에 보여줄 작은 썸네일(중앙 영역만).
    static func thumbnail(from pixelBuffer: CVPixelBuffer, maxSide: CGFloat = 240) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        // Vision 좌표(좌하단 원점)와 CIImage 좌표가 같으므로 그대로 쓴다.
        let crop = CGRect(x: extent.minX + extent.width * regionOfInterest.minX,
                          y: extent.minY + extent.height * regionOfInterest.minY,
                          width: extent.width * regionOfInterest.width,
                          height: extent.height * regionOfInterest.height)
        let scale = maxSide / max(crop.width, crop.height)
        let output = image.cropped(to: crop).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}
