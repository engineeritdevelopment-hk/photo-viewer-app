import SwiftUI

/// Analysis options, progress, stale hints, and people — one block.
struct LibraryAnalysisSection: View {
    @Bindable var model: LibraryViewModel
    var showPeopleBar: Bool
    var onShowPeople: () -> Void
    var onHidePeople: () -> Void
    @State private var isClearConfirmPresented = false

    private var showsPeopleHiddenStrip: Bool {
        !showPeopleBar && !model.project.personGroups.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            analysisBar

            if showPeopleBar {
                LibraryPeopleBar(model: model, onHide: onHidePeople, embedded: true)
            } else if showsPeopleHiddenStrip {
                peopleHiddenStrip
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(alignment: .bottom) { Divider() }
        .confirmationDialog(
            "Clear analysis data?",
            isPresented: $isClearConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                model.clearAnalysisData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Categories, object names, suggested titles, and people will be removed. Your photos and albums stay.")
        }
    }

    private var analysisBar: some View {
        HStack(spacing: 10) {
            LibraryAnalysisControls(model: model)

            Spacer(minLength: 8)

            if let error = model.activity.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            } else if let progress = activeProgress {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 88)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(progress.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.shouldShowAnalysisStaleBanner, let hint = model.analysisStaleHint {
                Text(staleSummary(hint))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(staleDetail(hint))
                Button {
                    model.dismissAnalysisStaleBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Dismiss until the library changes again")
            } else {
                Text(lastAnalysisLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Clear") {
                isClearConfirmPresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isAnalysisRunning)
            .help("Remove categories, suggested titles, object names, and people. Photos stay in the library.")
        }
    }

    private var activeProgress: (title: String, fraction: Double?)? {
        let activity = model.activity
        if activity.isCataloging {
            return counted("Indexing", done: activity.catalogScanned, total: activity.catalogTotal)
        }
        if activity.isSearchingFaces {
            return counted("Searching faces", done: activity.faceSearchDone, total: activity.faceSearchTotal)
        }
        if activity.isFaceProcessing {
            return counted("Finding faces", done: activity.facesProcessed, total: activity.faceTotal)
        }
        if activity.isAnalyzing {
            let title = activity.analysisTitle.replacingOccurrences(of: "…", with: "")
            return counted(title, done: activity.analyzed, total: activity.analyzeTotal)
        }
        if activity.isMetadataing {
            return counted("Reading metadata", done: activity.metadataDone, total: activity.metadataTotal)
        }
        if activity.isGeocoding {
            return counted("Resolving places", done: activity.geocoded, total: activity.geocodeTotal)
        }
        if activity.isExporting {
            return counted("Exporting", done: activity.exportCopied, total: activity.exportTotal)
        }
        return nil
    }

    private func counted(_ title: String, done: Int, total: Int?) -> (title: String, fraction: Double?) {
        guard let total, total > 0 else {
            return ("\(title)…", nil)
        }
        return ("\(title) \(done)/\(total)", min(1, Double(done) / Double(total)))
    }

    private func staleSummary(_ hint: AnalysisStaleHint) -> String {
        if hint.neverAnalyzed { return "Not analyzed yet" }
        if hint.newPhotoCount > 0 {
            let plural = hint.newPhotoCount == 1 ? "photo" : "photos"
            return "\(hint.newPhotoCount) new \(plural)"
        }
        return "Library changed"
    }

    private func staleDetail(_ hint: AnalysisStaleHint) -> String {
        let needsToggles = !model.categoryDetectionOn && !model.objectDetectionOn && !model.analyzeFacesOn
        let toggleNote = needsToggles ? "Turn on Categories, Objects, and/or Faces, then choose Run. " : ""
        if hint.neverAnalyzed {
            return toggleNote + "Run analysis to detect categories, objects, and people."
        }
        if hint.sourcesChanged, hint.newPhotoCount > 0 {
            let plural = hint.newPhotoCount == 1 ? "photo" : "photos"
            return toggleNote + "You added a source and \(hint.newPhotoCount) new \(plural) were indexed."
        }
        if hint.sourcesChanged {
            return toggleNote + "You added or removed a source."
        }
        let plural = hint.newPhotoCount == 1 ? "photo was" : "photos were"
        return toggleNote + "\(hint.newPhotoCount) new \(plural) indexed since the last analysis."
    }

    private var peopleHiddenStrip: some View {
        HStack(spacing: 8) {
            Text("People hidden")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Show people", action: onShowPeople)
                .controlSize(.mini)
                .buttonStyle(.bordered)
        }
    }

    private var lastAnalysisLabel: String {
        guard let date = model.project.analysisCheckpoint?.completedAt else {
            return "Not analyzed yet"
        }
        return "Last analysis \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var panelBackground: Color {
        Color(nsColor: .underPageBackgroundColor).opacity(0.35)
    }
}