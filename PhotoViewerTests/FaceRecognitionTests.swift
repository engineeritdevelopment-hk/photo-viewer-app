import CoreGraphics
import XCTest
@testable import Photo_Viewer

final class FaceRecognitionTests: XCTestCase {
    func testSimilarityKeepsTheTemplateInPlace() {
        let template = FaceAlignment.arcFaceTemplate
        let transform = FaceSimilarityTransform.estimate(from: template, to: template)
        XCTAssertNotNil(transform)
        guard let transform else { return }
        XCTAssertEqual(transform.a, 1, accuracy: 0.001)
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
        XCTAssertEqual(transform.tx, 0, accuracy: 0.001)
        XCTAssertEqual(transform.ty, 0, accuracy: 0.001)
    }

    func testSimilarityRecoversTranslation() {
        let destination = FaceAlignment.arcFaceTemplate
        let source = destination.map { SIMD2($0.x + 12, $0.y - 5) }
        let transform = FaceSimilarityTransform.estimate(from: source, to: destination)
        XCTAssertNotNil(transform)
        guard let transform else { return }
        XCTAssertEqual(transform.a, 1, accuracy: 0.001)
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
        XCTAssertEqual(transform.tx, -12, accuracy: 0.001)
        XCTAssertEqual(transform.ty, 5, accuracy: 0.001)
        let back = transform.sourcePoint(forTemplate: destination[0])
        XCTAssertEqual(back.x, source[0].x, accuracy: 0.01)
        XCTAssertEqual(back.y, source[0].y, accuracy: 0.01)
    }

    func testSimilarityRecoversQuarterTurn() {
        let source: [SIMD2<Float>] = [
            SIMD2(10, 10), SIMD2(20, 10), SIMD2(15, 16), SIMD2(12, 22), SIMD2(18, 22),
        ]
        let destination = source.map { SIMD2(-$0.y, $0.x) }
        let transform = FaceSimilarityTransform.estimate(from: source, to: destination)
        XCTAssertNotNil(transform)
        guard let transform else { return }
        XCTAssertEqual(transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(transform.b, 1, accuracy: 0.001)
    }

    func testThumbnailPrefersFrontalFaceOverLargerProfile() {
        let front = FaceAlignment.AlignedFace(
            image: solidFace(red: 1, green: 1, blue: 1)!,
            area: 80,
            yaw: 0.1,
            normalizedRect: .zero
        )
        let side = FaceAlignment.AlignedFace(
            image: solidFace(red: 2, green: 2, blue: 2)!,
            area: 400,
            yaw: 1.1,
            normalizedRect: .zero
        )
        let picked = FaceAlignment.preferredThumbnail(from: [side, front])
        XCTAssertEqual(picked?.yaw, front.yaw)
    }

    func testThumbnailUsesLargestFrontalFace() {
        let small = FaceAlignment.AlignedFace(
            image: solidFace(red: 1, green: 1, blue: 1)!,
            area: 40,
            yaw: 0.1,
            normalizedRect: .zero
        )
        let large = FaceAlignment.AlignedFace(
            image: solidFace(red: 2, green: 2, blue: 2)!,
            area: 200,
            yaw: 0.2,
            normalizedRect: .zero
        )
        let picked = FaceAlignment.preferredThumbnail(from: [small, large])
        XCTAssertEqual(picked?.area, large.area)
    }

    func testEmbeddingIsUnitLength() {
        var values = [Float](repeating: 0, count: FaceEmbedding.length)
        values[0] = 3
        values[1] = 4
        let embedding = FaceEmbedding(values: values)
        XCTAssertNotNil(embedding)
        guard let embedding else { return }
        XCTAssertEqual(embedding.cosineSimilarity(to: embedding), 1, accuracy: 0.001)
        XCTAssertNil(FaceEmbedding(values: [Float](repeating: 0, count: FaceEmbedding.length)))
    }

    func testAdaFaceEmbedsAnAlignedFace() throws {
        XCTAssertTrue(AdaFaceEmbedder.isAvailable())
        let image = try XCTUnwrap(solidFace(red: 40, green: 80, blue: 120))
        let first = try XCTUnwrap(AdaFaceEmbedder.embedding(forAlignedFace: image))
        let second = try XCTUnwrap(AdaFaceEmbedder.embedding(forAlignedFace: image))
        XCTAssertEqual(first.values.count, 512)
        XCTAssertEqual(first.cosineSimilarity(to: second), 1, accuracy: 0.001)
        var magnitude: Float = 0
        for value in first.values {
            magnitude += value * value
        }
        XCTAssertEqual(magnitude, 1, accuracy: 0.02)
    }

    func testFaceNameUsesTheCloserNamedPerson() throws {
        let ada = try XCTUnwrap(axisEmbedding(0))
        let bob = try XCTUnwrap(axisEmbedding(1))
        let face = UUID()
        let labels = FaceNameMatcher.labels(
            faceIDs: [face],
            faceEmbeddings: [face: ada],
            people: [(name: "Ada", embedding: ada), (name: "Bob", embedding: bob)]
        )
        XCTAssertEqual(labels[face], "Ada")
    }

    func testFaceNameFallsBackWhenTheOnlyPersonHasNoEmbedding() {
        let face = UUID()
        let labels = FaceNameMatcher.labels(
            faceIDs: [face],
            faceEmbeddings: [:],
            people: [(name: "Ada", embedding: nil)]
        )
        XCTAssertEqual(labels[face], "Ada")
    }

    func testHighlightKeepsTheMatchingFace() throws {
        let ada = try XCTUnwrap(axisEmbedding(0))
        let other = try XCTUnwrap(axisEmbedding(1))
        let adaFace = UUID()
        let otherFace = UUID()
        let matches = FaceNameMatcher.matchingFaceIDs(
            faceIDs: [adaFace, otherFace],
            faceEmbeddings: [adaFace: ada, otherFace: other],
            personEmbedding: ada
        )
        XCTAssertEqual(matches, [adaFace])
    }

    func testHighlightUsesTheOnlyFaceWhenThereIsNoEmbedding() {
        let face = UUID()
        let matches = FaceNameMatcher.matchingFaceIDs(
            faceIDs: [face],
            faceEmbeddings: [:],
            personEmbedding: nil
        )
        XCTAssertEqual(matches, [face])
    }

    func testFaceNameSkipsADifferentPerson() throws {
        let face = UUID()
        let labels = FaceNameMatcher.labels(
            faceIDs: [face],
            faceEmbeddings: [face: try XCTUnwrap(axisEmbedding(0))],
            people: [(name: "Bob", embedding: try XCTUnwrap(axisEmbedding(1)))]
        )
        XCTAssertNil(labels[face])
    }

    private func axisEmbedding(_ index: Int) -> FaceEmbedding? {
        var values = [Float](repeating: 0, count: FaceEmbedding.length)
        values[index] = 1
        return FaceEmbedding(values: values)
    }

    private func solidFace(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        let size = FaceAlignment.templateSize
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = red
            bytes[index + 1] = green
            bytes[index + 2] = blue
            bytes[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
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
}
