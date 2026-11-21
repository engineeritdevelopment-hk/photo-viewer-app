import CoreML
import CoreGraphics
import Foundation
import os

/// AdaFace IR-50 (WebFace4M), MIT, Kim, Jain, and Liu, CVPR 2022.
/// The bundled Core ML model takes one 112×112 ArcFace-aligned face and returns a 512-d embedding.
enum AdaFaceEmbedder {
    private static let logger = Logger(subsystem: "com.photoviewer.app", category: "faces")
    private static let lock = NSLock()
    private static var model: MLModel?
    private static var unavailable = false

    static func embedding(forAlignedFace image: CGImage) -> FaceEmbedding? {
        guard let model = loadModel() else { return nil }
        guard image.width == FaceAlignment.templateSize, image.height == FaceAlignment.templateSize else { return nil }
        guard let input = model.modelDescription.inputDescriptionsByName["face"],
              let constraint = input.imageConstraint
        else { return nil }
        do {
            let face = try MLFeatureValue(cgImage: image, constraint: constraint)
            let provider = try MLDictionaryFeatureProvider(dictionary: ["face": face])
            let prediction = try model.prediction(from: provider)
            guard let array = prediction.featureValue(for: "embedding")?.multiArrayValue else { return nil }
            return FaceEmbedding(values: vector(from: array))
        } catch {
            logger.error("AdaFace prediction failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func isAvailable() -> Bool {
        loadModel() != nil
    }

    private static func loadModel() -> MLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model { return model }
        if unavailable { return nil }
        let bundle = Bundle(for: AdaFaceBundleToken.self)
        guard let url = bundle.url(forResource: "AdaFace", withExtension: "mlmodelc") else {
            unavailable = true
            logger.error("AdaFace.mlmodelc is missing from the app bundle")
            return nil
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded
            return loaded
        } catch {
            unavailable = true
            logger.error("AdaFace failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func vector(from array: MLMultiArray) -> [Float] {
        let count = FaceEmbedding.length
        var values = [Float](repeating: 0, count: count)
        if array.shape.count == 2, array.shape[1].intValue == count {
            for index in 0 ..< count {
                values[index] = array[[0 as NSNumber, NSNumber(value: index)]].floatValue
            }
            return values
        }
        let readable = min(array.count, count)
        for index in 0 ..< readable {
            values[index] = array[index].floatValue
        }
        return values
    }
}

private final class AdaFaceBundleToken {}
