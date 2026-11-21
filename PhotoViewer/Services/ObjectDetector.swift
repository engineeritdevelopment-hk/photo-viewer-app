import CoreML
import Foundation
import ImageIO
import os

/// Open Images object names stored in the photo index.
enum ObjectLabels {
    static func encode(_ names: [String]) -> String? {
        let unique = normalized(names)
        guard !unique.isEmpty else { return nil }
        return "|" + unique.joined(separator: "|") + "|"
    }

    static func decode(_ stored: String?) -> [String] {
        guard let stored else { return [] }
        return stored
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for name in names {
            let cleaned = name
                .replacingOccurrences(of: "_", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { continue }
            // The detector pads unused class slots with numeric names.
            guard key.unicodeScalars.contains(where: { !CharacterSet.decimalDigits.contains($0) }) else { continue }
            unique.append(cleaned)
        }
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// YOLOv8m trained on Open Images v7 (601 object names), exported to Core ML.
enum ObjectDetector {
    static let confidenceThreshold: Float = 0.35

    private static let logger = Logger(subsystem: "com.photoviewer.app", category: "objects")
    private static let lock = NSLock()
    private static var model: MLModel?
    private static var classNames: [String] = []
    private static var unavailable = false

    static func isAvailable() -> Bool {
        loadModel() != nil
    }

    static func labels(at url: URL) -> [String] {
        guard let model = loadModel(), let image = thumbnail(at: url) else { return [] }
        guard let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            return []
        }
        var locked = false
        do {
            let imageValue = try MLFeatureValue(cgImage: image, constraint: constraint)
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "image": imageValue,
                "iouThreshold": MLFeatureValue(double: 0.45),
                "confidenceThreshold": MLFeatureValue(double: Double(confidenceThreshold)),
            ])
            lock.lock()
            locked = true
            let names = classNames
            let prediction = try model.prediction(from: provider)
            lock.unlock()
            locked = false
            return ObjectLabels.normalized(readNames(from: prediction, classNames: names))
        } catch {
            if locked { lock.unlock() }
            logger.error("Object detection failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func readNames(from prediction: MLFeatureProvider, classNames: [String]) -> [String] {
        guard let confidence = prediction.featureValue(for: "confidence")?.multiArrayValue else { return [] }
        let shape = confidence.shape.map(\.intValue)
        guard shape.count == 2, shape[0] > 0, shape[1] > 0 else { return [] }
        var found: [String] = []
        for box in 0..<shape[0] {
            var bestClass = 0
            var bestScore: Float = 0
            for index in 0..<shape[1] {
                let score = confidence[[box as NSNumber, index as NSNumber]].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClass = index
                }
            }
            guard bestScore >= confidenceThreshold, bestClass < classNames.count else { continue }
            found.append(classNames[bestClass])
        }
        return found
    }

    private static func loadModel() -> MLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model { return model }
        if unavailable { return nil }
        let bundle = Bundle(for: ObjectDetectorBundleToken.self)
        guard let url = bundle.url(forResource: "ObjectDetector", withExtension: "mlmodelc") else {
            unavailable = true
            logger.error("ObjectDetector.mlmodelc is missing from the app bundle")
            return nil
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            classNames = loadClassNames(from: bundle)
            model = loaded
            return loaded
        } catch {
            unavailable = true
            logger.error("Object detector failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func loadClassNames(from bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "ObjectClasses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            logger.error("ObjectClasses.json is missing from the app bundle")
            return []
        }
        return names
    }

    private static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private final class ObjectDetectorBundleToken {}
