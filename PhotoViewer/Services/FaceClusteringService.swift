import Foundation

struct FaceClusteringService: Sendable {
    struct Output: Sendable {
        var groups: [PersonGroup]
        var pathToGroupIds: [String: [String]]
    }

    /// AdaFace cosine similarity on unit embeddings. Higher = more likely the same person.
    private let minimumCosine = FaceEmbedding.samePersonCosine
    private let unionFindFaceLimit = 4_000

    private struct FaceInstance {
        let photoPath: String?
        let embedding: FaceEmbedding
        /// Set for anchors representing an existing person group.
        let presetGroupId: String?
    }

    private struct DisjointSet {
        private var parent: [Int]

        init(count: Int) {
            parent = Array(0 ..< count)
        }

        mutating func find(_ x: Int) -> Int {
            if parent[x] == x { return x }
            parent[x] = find(parent[x])
            return parent[x]
        }

        mutating func union(_ a: Int, _ b: Int) {
            let rootA = find(a)
            let rootB = find(b)
            guard rootA != rootB else { return }
            parent[rootB] = rootA
        }

    }

    func cluster(
        paths: [String],
        existingGroups: [PersonGroup],
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async -> Output {
        let total = paths.count
        let existingById = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })

        var instances: [FaceInstance] = []
        instances.reserveCapacity(total * 2 + existingGroups.count)

        guard AdaFaceEmbedder.isAvailable() else {
            return Output(groups: existingGroups, pathToGroupIds: [:])
        }

        for group in existingGroups {
            guard let embedding = representativeEmbedding(for: group) else { continue }
            instances.append(
                FaceInstance(photoPath: nil, embedding: embedding, presetGroupId: group.id)
            )
        }

        for (index, path) in paths.enumerated() {
            if Task.isCancelled { break }
            let url = URL(fileURLWithPath: path)
            let embeddings: [FaceEmbedding] = autoreleasepool {
                FaceAlignment.alignedFaces(from: url).compactMap {
                    AdaFaceEmbedder.embedding(forAlignedFace: $0.image)
                }
            }
            for embedding in embeddings {
                instances.append(FaceInstance(photoPath: path, embedding: embedding, presetGroupId: nil))
            }
            if let onProgress, index % 8 == 7 || index == total - 1 {
                await onProgress(index + 1, total)
            }
        }

        guard !Task.isCancelled else {
            return Output(groups: existingGroups, pathToGroupIds: [:])
        }

        let clusterRoots = assignClusterIds(instances: instances, existingById: existingById)

        var groupsById: [String: PersonGroup] = [:]
        var pathToGroupIds: [String: [String]] = [:]

        for (index, instance) in instances.enumerated() {
            guard instance.photoPath != nil else { continue }
            guard let groupId = clusterRoots[index] else { continue }
            guard let path = instance.photoPath else { continue }

            if groupsById[groupId] == nil, let existing = existingById[groupId] {
                groupsById[groupId] = PersonGroup(
                    id: groupId,
                    displayName: existing.displayName,
                    memberPhotoPaths: [],
                    thumbnailPath: existing.thumbnailPath,
                    faceCropPath: existing.faceCropPath,
                    isLookedUp: existing.isLookedUp
                )
            }

            if var group = groupsById[groupId] {
                if !group.memberPhotoPaths.contains(path) {
                    group.memberPhotoPaths.append(path)
                }
                if group.thumbnailPath == nil { group.thumbnailPath = path }
                groupsById[groupId] = group
            } else {
                groupsById[groupId] = PersonGroup(
                    id: groupId,
                    displayName: nil,
                    memberPhotoPaths: [path],
                    thumbnailPath: path,
                    faceCropPath: nil
                )
            }

            pathToGroupIds[path, default: []].append(groupId)
        }

        for (path, ids) in pathToGroupIds {
            pathToGroupIds[path] = Array(Set(ids))
        }

        for id in Array(groupsById.keys) {
            guard var group = groupsById[id], group.faceCropPath == nil else { continue }
            guard let path = group.thumbnailPath ?? group.memberPhotoPaths.first else { continue }
            let crop = autoreleasepool {
                FaceAlignment.preferredThumbnail(from: URL(fileURLWithPath: path))
            }
            guard let crop else { continue }
            group.faceCropPath = FaceThumbnailWriter.save(cgImage: crop, groupId: id)
            groupsById[id] = group
        }

        var groups = Array(groupsById.values).filter { !$0.memberPhotoPaths.isEmpty }
        groups.sort {
            if $0.memberPhotoPaths.count != $1.memberPhotoPaths.count {
                return $0.memberPhotoPaths.count > $1.memberPhotoPaths.count
            }
            return $0.id < $1.id
        }

        if let onProgress {
            await onProgress(total, total)
        }
        return Output(groups: groups, pathToGroupIds: pathToGroupIds)
    }

    /// One group id per instance index; anchors share the id of their cluster.
    private func assignClusterIds(
        instances: [FaceInstance],
        existingById: [String: PersonGroup]
    ) -> [String?] {
        guard !instances.isEmpty else { return [] }

        if instances.count > unionFindFaceLimit {
            return assignClusterIdsGreedy(instances: instances, existingById: existingById)
        }

        var set = DisjointSet(count: instances.count)
        for i in 0 ..< instances.count {
            for j in (i + 1) ..< instances.count {
                if similarity(instances[i].embedding, instances[j].embedding) >= minimumCosine {
                    set.union(i, j)
                }
            }
        }

        var rootToMembers: [Int: [Int]] = [:]
        for index in instances.indices {
            let root = set.find(index)
            rootToMembers[root, default: []].append(index)
        }

        var rootToGroupId: [Int: String] = [:]
        for (root, members) in rootToMembers {
            rootToGroupId[root] = canonicalGroupId(
                members: members,
                instances: instances,
                existingById: existingById
            )
        }

        return instances.indices.map { index in
            let root = set.find(index)
            return rootToGroupId[root]
        }
    }

    private func assignClusterIdsGreedy(
        instances: [FaceInstance],
        existingById: [String: PersonGroup]
    ) -> [String?] {
        var known: [(id: String, embedding: FaceEmbedding)] = []
        for group in existingById.values {
            if let embedding = representativeEmbedding(for: group) {
                known.append((group.id, embedding))
            }
        }

        return instances.map { instance in
            if let preset = instance.presetGroupId {
                return preset
            }
            if let match = nearestGroup(embedding: instance.embedding, among: known, threshold: minimumCosine) {
                return match
            }
            let id = UUID().uuidString
            known.append((id, instance.embedding))
            return id
        }
    }

    private func canonicalGroupId(
        members: [Int],
        instances: [FaceInstance],
        existingById: [String: PersonGroup]
    ) -> String {
        let presetIds = members.compactMap { instances[$0].presetGroupId }
        if !presetIds.isEmpty {
            return pickBestExistingId(presetIds, existingById: existingById)
        }
        return UUID().uuidString
    }

    private func pickBestExistingId(_ ids: [String], existingById: [String: PersonGroup]) -> String {
        let unique = Array(Set(ids))
        return unique.max { lhs, rhs in
            score(lhs, existingById: existingById) < score(rhs, existingById: existingById)
        } ?? unique[0]
    }

    private func score(_ id: String, existingById: [String: PersonGroup]) -> Int {
        let group = existingById[id]
        let photoScore = group?.memberPhotoPaths.count ?? 0
        let nameScore = (group?.displayName?.isEmpty == false) ? 1_000 : 0
        return photoScore + nameScore
    }

    private func nearestGroup(
        embedding: FaceEmbedding,
        among candidates: [(id: String, embedding: FaceEmbedding)],
        threshold: Float
    ) -> String? {
        var best: (id: String, similarity: Float)?
        for candidate in candidates {
            let score = similarity(embedding, candidate.embedding)
            guard score >= threshold else { continue }
            if best == nil || score > best!.similarity {
                best = (candidate.id, score)
            }
        }
        return best?.id
    }

    private func similarity(_ a: FaceEmbedding, _ b: FaceEmbedding) -> Float {
        a.cosineSimilarity(to: b)
    }

    /// Re-align the person's photo. Saved crops from the old matcher are not ArcFace-aligned.
    private func representativeEmbedding(for group: PersonGroup) -> FaceEmbedding? {
        let candidates = [group.thumbnailPath, group.memberPhotoPaths.first, group.faceCropPath]
        for path in candidates {
            guard let path else { continue }
            let embedding = autoreleasepool { () -> FaceEmbedding? in
                guard let face = FaceAlignment.preferredThumbnail(from: URL(fileURLWithPath: path)) else { return nil }
                return AdaFaceEmbedder.embedding(forAlignedFace: face)
            }
            if let embedding { return embedding }
        }
        return nil
    }
}