import Foundation

actor AnalysisPipeline {
    private let maxConcurrent = 3
    private var paused = false

    func setPaused(_ value: Bool) {
        paused = value
    }

    func process(
        paths: [String],
        semanticOn: Bool,
        smartTitlesOn: Bool,
        facesOn: Bool,
        index: PhotoIndexStore,
        placeService: PlaceLabelService,
        onMetadata: @escaping @MainActor (Int, Int) async -> Void,
        onAnalysis: @escaping @MainActor (Int, Int) async -> Void,
        onGeocode: @escaping @MainActor (Int, Int) async -> Void,
        onFaces: @escaping @MainActor (Int, Int) async -> Void,
        onFacePhaseStarted: @escaping @MainActor () async -> Void,
        personGroups: @escaping @MainActor () async -> [PersonGroup],
        onPersonGroups: @escaping @MainActor ([PersonGroup]) async -> Void,
        onSmartTitle: @escaping @MainActor (String, String) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        let total = paths.count
        var metadataDone = 0

        await withTaskGroup(of: Void.self) { group in
            var active = 0
            var iterator = paths.makeIterator()

            while active < maxConcurrent, let path = iterator.next() {
                active += 1
                group.addTask {
                    await self.processOne(
                        path: path,
                        semanticOn: semanticOn,
                        smartTitlesOn: smartTitlesOn,
                        index: index,
                        onSmartTitle: onSmartTitle
                    )
                    await onMetadata(metadataDone, total)
                }
            }

            while let _ = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                metadataDone += 1
                await onMetadata(metadataDone, total)
                if semanticOn {
                    await onAnalysis(metadataDone, total)
                }
                if let path = iterator.next() {
                    active += 1
                    group.addTask {
                        await self.processOne(
                            path: path,
                            semanticOn: semanticOn,
                            smartTitlesOn: smartTitlesOn,
                            index: index,
                            onSmartTitle: onSmartTitle
                        )
                    }
                }
            }
        }

        guard !Task.isCancelled else { return }

        var geocoded = 0
        let gpsTotal = paths.count
        for path in paths {
            if Task.isCancelled { break }
            if let record = try? await index.record(for: path),
               record.hasGPS,
               let lat = record.latitude,
               let lon = record.longitude,
               record.placeLabel == nil,
               let label = await placeService.label(latitude: lat, longitude: lon) {
                try? await index.updatePlaceLabel(path: path, placeLabel: label)
            }
            geocoded += 1
            await onGeocode(geocoded, gpsTotal)
        }

        if facesOn, !Task.isCancelled {
            await onFacePhaseStarted()
            await onFaces(0, paths.count)
            let groups = await personGroups()
            let faceService = FaceClusteringService()
            let result = await faceService.cluster(paths: paths, existingGroups: groups) { done, faceTotal in
                await onFaces(done, faceTotal)
            }
            await onPersonGroups(result.groups)
            for update in result.pathToGroupIds {
                try? await index.updatePersonGroups(path: update.key, groupIds: update.value)
            }
            await onFaces(paths.count, paths.count)
        }
    }

    private func processOne(
        path: String,
        semanticOn: Bool,
        smartTitlesOn: Bool,
        index: PhotoIndexStore,
        onSmartTitle: @escaping @MainActor (String, String) async -> Void
    ) async {
        while paused { await Task.yield() }
        let url = URL(fileURLWithPath: path)
        let meta = MetadataReader.read(url: url)
        try? await index.updateMetadata(
            path: path,
            takenAt: meta.takenAt,
            cameraMake: meta.cameraMake,
            cameraModel: meta.cameraModel,
            latitude: meta.latitude,
            longitude: meta.longitude,
            hasGPS: meta.hasGPS,
            width: meta.width,
            height: meta.height,
            isScreenshot: meta.isScreenshot
        )

        if semanticOn {
            let analysis = await PhotoAnalyzer.analyze(
                url: url,
                semanticGroupingOn: true,
                smartTitlesOn: smartTitlesOn
            )
            try? await index.updateAnalysis(
                path: path,
                sceneLabels: analysis.sceneLabels,
                ocrSnippet: analysis.ocrSnippet,
                semanticCategory: analysis.semanticCategory,
                source: analysis.source
            )
            if smartTitlesOn, let title = analysis.suggestedTitle, !title.isEmpty {
                await onSmartTitle(path, title)
            }
        }
    }
}