import Foundation
import ImageIO
import Vision

enum FaceCropExtractor {
    /// Extra margin around Vision face bounds (fraction of face width/height per side).
    private static let cropPaddingRatio: CGFloat = 0.32

    static func loadCGImage(url: URL, maxPixel: Int = 1024) -> CGImage? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func faceCrops(from url: URL) -> [CGImage] {
        guard let cgImage = loadCGImage(url: url) else { return [] }
        return faceCrops(in: cgImage)
    }

    static func largestFace(from url: URL) -> CGImage? {
        let crops = faceCrops(from: url)
        return crops.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }

    static func faceCrops(in cgImage: CGImage) -> [CGImage] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let results = request.results, !results.isEmpty else { return [] }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        return results.compactMap { observation -> CGImage? in
            let box = observation.boundingBox
            let face = CGRect(
                x: box.origin.x * width,
                y: (1 - box.origin.y - box.size.height) * height,
                width: box.size.width * width,
                height: box.size.height * height
            )
            let cropRect = paddedFaceRect(face, within: imageBounds).integral
            return cgImage.cropping(to: cropRect)
        }
    }

    private static func paddedFaceRect(_ face: CGRect, within bounds: CGRect) -> CGRect {
        let padX = face.width * cropPaddingRatio
        let padY = face.height * cropPaddingRatio
        var expanded = face.insetBy(dx: -padX, dy: -padY)
        expanded = expanded.intersection(bounds)
        guard expanded.width > 1, expanded.height > 1 else { return face }
        return expanded
    }
}