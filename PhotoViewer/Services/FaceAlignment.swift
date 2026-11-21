import CoreGraphics
import Foundation
import Vision

enum FaceAlignment {
    static let templateSize = 112
    /// InsightFace ArcFace five-point template: image-left eye, image-right eye, nose tip, image-left mouth, image-right mouth.
    static let arcFaceTemplate: [SIMD2<Float>] = [
        SIMD2(38.2946, 51.6963),
        SIMD2(73.5318, 51.5014),
        SIMD2(56.0252, 71.7366),
        SIMD2(41.5493, 92.3655),
        SIMD2(70.7299, 92.2041),
    ]

    /// Yaw at or below this (radians, about 26°) is treated as facing the camera.
    static let frontalYawLimit: Float = 0.45

    struct AlignedFace: Identifiable {
        var id = UUID()
        var image: CGImage
        var area: CGFloat
        /// Absolute yaw in radians. 0 faces the camera.
        var yaw: Float
        /// Face bounds in the source image, origin at the top-left, each axis 0...1.
        var normalizedRect: CGRect
    }

    static func alignedFaces(from url: URL) -> [AlignedFace] {
        guard let cgImage = FaceCropExtractor.loadCGImage(url: url, maxPixel: 2048) else { return [] }
        return alignedFaces(in: cgImage)
    }

    /// Front-facing face when one exists; otherwise the face turned least to the side.
    static func preferredThumbnail(from faces: [AlignedFace]) -> AlignedFace? {
        guard !faces.isEmpty else { return nil }
        let frontal = faces.filter { $0.yaw <= frontalYawLimit }
        if !frontal.isEmpty {
            return frontal.max { $0.area < $1.area }
        }
        return faces.min { lhs, rhs in
            if lhs.yaw != rhs.yaw { return lhs.yaw < rhs.yaw }
            return lhs.area > rhs.area
        }
    }

    static func preferredThumbnail(from url: URL) -> CGImage? {
        preferredThumbnail(from: alignedFaces(from: url))?.image
    }

    /// A face inside the user's rectangle. Uses a detected face when the rectangle covers one, otherwise looks inside the crop.
    static func face(framedBy normalizedRect: CGRect, among faces: [AlignedFace], image: CGImage) -> AlignedFace? {
        let expanded = normalizedRect.insetBy(dx: -0.02, dy: -0.02)
        let hits = faces.filter { $0.normalizedRect.intersects(expanded) }
        if let face = preferredThumbnail(from: hits) { return face }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let pixel = CGRect(
            x: normalizedRect.origin.x * bounds.width,
            y: normalizedRect.origin.y * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        ).integral.intersection(bounds)
        guard pixel.width > 16, pixel.height > 16, let crop = image.cropping(to: pixel) else { return nil }
        return preferredThumbnail(from: alignedFaces(in: crop))
    }

    static func largestAlignedFace(from url: URL) -> CGImage? {
        preferredThumbnail(from: url)
    }

    static func alignedFaces(in cgImage: CGImage) -> [AlignedFace] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let observations = request.results, !observations.isEmpty else { return [] }
        let width = cgImage.width
        let height = cgImage.height
        guard let pixels = rgbaPixels(from: cgImage) else { return [] }
        return observations.compactMap { observation in
            alignedFace(observation, pixels: pixels, width: width, height: height)
        }
    }

    private static func alignedFace(
        _ observation: VNFaceObservation,
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> AlignedFace? {
        let faceWidth = observation.boundingBox.width * CGFloat(width)
        let faceHeight = observation.boundingBox.height * CGFloat(height)
        guard faceWidth >= 32, faceHeight >= 32 else { return nil }
        guard let source = landmarkPoints(observation, width: width, height: height) else { return nil }
        guard let transform = FaceSimilarityTransform.estimate(from: source, to: arcFaceTemplate),
              transform.meanError(from: source, to: arcFaceTemplate) <= 10
        else { return nil }
        guard let image = warp(pixels: pixels, width: width, height: height, transform: transform) else { return nil }
        let box = observation.boundingBox
        let rect = CGRect(
            x: box.origin.x,
            y: 1 - box.origin.y - box.height,
            width: box.width,
            height: box.height
        )
        let yaw = abs(observation.yaw?.floatValue ?? 0)
        return AlignedFace(image: image, area: faceWidth * faceHeight, yaw: yaw, normalizedRect: rect)
    }

    /// Five points in top-left, y-down pixels, ordered like `arcFaceTemplate`.
    private static func landmarkPoints(_ observation: VNFaceObservation, width: Int, height: Int) -> [SIMD2<Float>]? {
        guard let landmarks = observation.landmarks,
              let imageLeftEye = center(landmarks.leftEye, observation: observation, width: width, height: height),
              let imageRightEye = center(landmarks.rightEye, observation: observation, width: width, height: height),
              let nose = noseTip(landmarks, observation: observation, width: width, height: height),
              let lips = points(landmarks.outerLips, observation: observation, width: width, height: height),
              lips.count >= 2
        else { return nil }

        let eyeSpan = hypot(imageRightEye.x - imageLeftEye.x, imageRightEye.y - imageLeftEye.y)
        guard eyeSpan >= 2 else { return nil }
        // Vision's left and right match the image, which is the ArcFace template order.
        let axis = imageRightEye - imageLeftEye
        var imageLeftMouth: SIMD2<Float>?
        var imageRightMouth: SIMD2<Float>?
        var minScore = Float.greatestFiniteMagnitude
        var maxScore = -Float.greatestFiniteMagnitude
        for point in lips {
            let offset = point - nose
            let score = offset.x * axis.x + offset.y * axis.y
            if score < minScore {
                minScore = score
                imageLeftMouth = point
            }
            if score > maxScore {
                maxScore = score
                imageRightMouth = point
            }
        }
        guard let imageLeftMouth, let imageRightMouth, imageLeftMouth != imageRightMouth else { return nil }
        return [imageLeftEye, imageRightEye, nose, imageLeftMouth, imageRightMouth]
    }

    private static func noseTip(
        _ landmarks: VNFaceLandmarks2D,
        observation: VNFaceObservation,
        width: Int,
        height: Int
    ) -> SIMD2<Float>? {
        if let crest = points(landmarks.noseCrest, observation: observation, width: width, height: height),
           let tip = crest.last {
            return tip
        }
        return center(landmarks.nose, observation: observation, width: width, height: height)
    }

    private static func center(
        _ region: VNFaceLandmarkRegion2D?,
        observation: VNFaceObservation,
        width: Int,
        height: Int
    ) -> SIMD2<Float>? {
        guard let points = points(region, observation: observation, width: width, height: height), !points.isEmpty else {
            return nil
        }
        let sum = points.reduce(SIMD2<Float>.zero, +)
        return sum / Float(points.count)
    }

    /// Landmark points are normalized inside the face box, origin at the bottom-left of that box.
    private static func points(
        _ region: VNFaceLandmarkRegion2D?,
        observation: VNFaceObservation,
        width: Int,
        height: Int
    ) -> [SIMD2<Float>]? {
        guard let region else { return nil }
        let box = observation.boundingBox
        let imageWidth = Float(width)
        let imageHeight = Float(height)
        return region.normalizedPoints.map { point in
            let x = Float(box.origin.x) + Float(point.x) * Float(box.width)
            let y = Float(box.origin.y) + Float(point.y) * Float(box.height)
            return SIMD2(x * imageWidth, (1 - y) * imageHeight)
        }
    }

    private static func rgbaPixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let wrote = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return wrote ? bytes : nil
    }

    private static func warp(pixels: [UInt8], width: Int, height: Int, transform: FaceSimilarityTransform) -> CGImage? {
        let size = templateSize
        var output = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let source = transform.sourcePoint(forTemplate: SIMD2(Float(x) + 0.5, Float(y) + 0.5))
                let color = sample(pixels, width: width, height: height, x: source.x - 0.5, y: source.y - 0.5)
                let index = (y * size + x) * 4
                output[index] = color.0
                output[index + 1] = color.1
                output[index + 2] = color.2
                output[index + 3] = 255
            }
        }
        let data = Data(output) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func sample(_ pixels: [UInt8], width: Int, height: Int, x: Float, y: Float) -> (UInt8, UInt8, UInt8) {
        guard x >= 0, y >= 0, x < Float(width - 1), y < Float(height - 1) else { return (0, 0, 0) }
        let x0 = Int(x)
        let y0 = Int(y)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        func pixel(_ px: Int, _ py: Int) -> SIMD3<Float> {
            let index = (py * width + px) * 4
            return SIMD3(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]))
        }
        let top = pixel(x0, y0) * (1 - tx) + pixel(x1, y0) * tx
        let bottom = pixel(x0, y1) * (1 - tx) + pixel(x1, y1) * tx
        let mixed = top * (1 - ty) + bottom * ty
        return (byte(mixed.x), byte(mixed.y), byte(mixed.z))
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
