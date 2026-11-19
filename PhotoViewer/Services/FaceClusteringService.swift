import Foundation
import Vision

struct FaceClusteringService: Sendable {
    struct Output: Sendable {
        var groups: [PersonGroup]
        var pathToGroupIds: [String: [String]]
    }

    /// Vision feature-print distance: lower = more similar faces.
    private let clusterThreshold: Float = 0.58
    private let unionFindFaceLimit = 4_000

    private struct FaceInstance {
        let photoPath: String?
        let crop: CGImage?
        let print: VNFeaturePrintObservation
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

        for group in existingGroups {
            guard let print = representativePrint(for: group) else { continue }
            instances.append(
                FaceInstance(photoPath: nil, crop: nil, print: print, presetGroupId: group.id)
            )
        }

        for (index, path) in paths.enumerated() {
            if Task.isCancelled { break }
            let url = URL(fileURLWithPath: path)
            for crop in FaceCropExtractor.faceCrops(from: url) {
                guard let print = featurePrint(cgImage: crop) else { continue }
                instances.append(FaceInstance(photoPath: path, crop: crop, print: print, presetGroupId: nil))
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
                    faceCropPath: existing.faceCropPath
                )
            }

            if var group = groupsById[groupId] {
                if !group.memberPhotoPaths.contains(path) {
                    group.memberPhotoPaths.append(path)
                }
                if group.thumbnailPath == nil { group.thumbnailPath = path }
                if group.faceCropPath == nil, let crop = instance.crop {
                    group.faceCropPath = FaceThumbnailWriter.save(cgImage: crop, groupId: groupId)
                }
                groupsById[groupId] = group
            } else {
                let cropPath = instance.crop.flatMap { FaceThumbnailWriter.save(cgImage: $0, groupId: groupId) }
                groupsById[groupId] = PersonGroup(
                    id: groupId,
                    displayName: nil,
                    memberPhotoPaths: [path],
                    thumbnailPath: path,
                    faceCropPath: cropPath
                )
            }

            pathToGroupIds[path, default: []].append(groupId)
        }

        for (path, ids) in pathToGroupIds {
            pathToGroupIds[path] = Array(Set(ids))
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
                if let gap = distance(instances[i].print, instances[j].print), gap < clusterThreshold {
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
        var prints: [(id: String, print: VNFeaturePrintObservation)] = []
        for group in existingById.values {
            if let print = representativePrint(for: group) {
                prints.append((group.id, print))
            }
        }

        return instances.map { instance in
            if let preset = instance.presetGroupId {
                return preset
            }
            if let match = nearestGroup(print: instance.print, among: prints, threshold: clusterThreshold) {
                return match
            }
            let id = UUID().uuidString
            prints.append((id, instance.print))
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
        print: VNFeaturePrintObservation,
        among candidates: [(id: String, print: VNFeaturePrintObservation)],
        threshold: Float
    ) -> String? {
        var best: (id: String, distance: Float)?
        for candidate in candidates {
            guard let distance = distance(print, candidate.print), distance < threshold else { continue }
            if best == nil || distance < best!.distance {
                best = (candidate.id, distance)
            }
        }
        return best?.id
    }

    private func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value: Float = 0
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return nil
        }
    }

    private func representativePrint(for group: PersonGroup) -> VNFeaturePrintObservation? {
        if let crop = group.faceCropPath {
            return featurePrint(for: URL(fileURLWithPath: crop))
        }
        if let photo = group.thumbnailPath ?? group.memberPhotoPaths.first {
            return featurePrint(for: URL(fileURLWithPath: photo))
        }
        return nil
    }

    private func featurePrint(for url: URL) -> VNFeaturePrintObservation? {
        if url.path.contains("face-crops") {
            guard let cgImage = FaceCropExtractor.loadCGImage(url: url, maxPixel: 512) else { return nil }
            return featurePrint(cgImage: cgImage)
        }
        guard let crop = FaceCropExtractor.largestFace(from: url) else { return nil }
        return featurePrint(cgImage: crop)
    }

    private func featurePrint(cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }
}