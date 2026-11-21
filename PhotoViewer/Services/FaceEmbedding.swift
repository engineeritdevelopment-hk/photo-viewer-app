import Accelerate
import Foundation

/// Unit-length 512-d AdaFace identity vector.
struct FaceEmbedding: Sendable {
    static let length = 512
    /// Same-person cutoff for AdaFace unit embeddings.
    static let samePersonCosine: Float = 0.40

    var values: [Float]

    init?(values: [Float]) {
        guard values.count == Self.length, values.allSatisfy(\.isFinite) else { return nil }
        var normalized = values
        var magnitudeSquared: Float = 0
        vDSP_svesq(normalized, 1, &magnitudeSquared, vDSP_Length(Self.length))
        guard magnitudeSquared > 1e-8 else { return nil }
        var scale = 1 / sqrt(magnitudeSquared)
        vDSP_vsmul(normalized, 1, &scale, &normalized, 1, vDSP_Length(Self.length))
        self.values = normalized
    }

    /// 1 is the same face. Both vectors are unit length, so this is their dot product.
    func cosineSimilarity(to other: FaceEmbedding) -> Float {
        var dot: Float = 0
        vDSP_dotpr(values, 1, other.values, 1, &dot, vDSP_Length(Self.length))
        return dot
    }
}

enum FaceNameMatcher {
    /// Names for faces in one photo. Uses the closest named person at or above the same-person cutoff.
    /// When a photo has one face and one named person but an embedding is missing, that name is used.
    static func labels(
        faceIDs: [UUID],
        faceEmbeddings: [UUID: FaceEmbedding],
        people: [(name: String, embedding: FaceEmbedding?)]
    ) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        let named = people.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !faceIDs.isEmpty, !named.isEmpty else { return labels }

        for faceID in faceIDs {
            guard let faceEmbedding = faceEmbeddings[faceID] else { continue }
            var best: (name: String, score: Float)?
            for person in named {
                guard let personEmbedding = person.embedding else { continue }
                let score = faceEmbedding.cosineSimilarity(to: personEmbedding)
                guard score >= FaceEmbedding.samePersonCosine else { continue }
                if best == nil || score > best!.score {
                    best = (person.name, score)
                }
            }
            if let best {
                labels[faceID] = best.name
            }
        }

        if labels.isEmpty, faceIDs.count == 1, named.count == 1, let faceID = faceIDs.first {
            let missingEmbedding = faceEmbeddings[faceID] == nil || named[0].embedding == nil
            if missingEmbedding {
                labels[faceID] = named[0].name
            }
        }
        return labels
    }

    /// Faces in a photo that belong to one filtered person.
    static func matchingFaceIDs(
        faceIDs: [UUID],
        faceEmbeddings: [UUID: FaceEmbedding],
        personEmbedding: FaceEmbedding?
    ) -> Set<UUID> {
        guard !faceIDs.isEmpty else { return [] }
        if let personEmbedding {
            let matches = Set(faceIDs.filter { faceID in
                guard let faceEmbedding = faceEmbeddings[faceID] else { return false }
                return faceEmbedding.cosineSimilarity(to: personEmbedding) >= FaceEmbedding.samePersonCosine
            })
            if !matches.isEmpty { return matches }
        }
        if faceIDs.count == 1, let only = faceIDs.first {
            return [only]
        }
        return []
    }
}
