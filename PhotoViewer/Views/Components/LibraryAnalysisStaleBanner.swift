import SwiftUI

struct LibraryAnalysisStaleBanner: View {
    @Bindable var model: LibraryViewModel
    var embedded: Bool = false

    var body: some View {
        if model.shouldShowAnalysisStaleBanner, let hint = model.analysisStaleHint {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)

                Text(message(for: hint))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Run") {
                    model.startAnalysis()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)

                Button {
                    model.dismissAnalysisStaleBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Dismiss until the library changes again")
            }
            .padding(.horizontal, embedded ? 10 : 12)
            .padding(.vertical, embedded ? 7 : 8)
            .background(Color.orange.opacity(embedded ? 0.14 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: embedded ? 8 : 0, style: .continuous))
            .overlay(alignment: .bottom) {
                if !embedded { Divider() }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var needsAnalysisToggles: Bool {
        !model.categoryDetectionOn && !model.analyzeFacesOn
    }

    private func message(for hint: AnalysisStaleHint) -> String {
        let toggleNote = needsAnalysisToggles
            ? "Turn on Categories and/or Faces, then choose Run. "
            : ""
        if hint.neverAnalyzed {
            return toggleNote + "Run analysis to detect categories and people for your indexed photos."
        }
        if hint.sourcesChanged, hint.newPhotoCount > 0 {
            let plural = hint.newPhotoCount == 1 ? "photo" : "photos"
            return toggleNote
                + "You added a source and \(hint.newPhotoCount) new \(plural) were indexed. Run analysis again so categories and faces include the new items."
        }
        if hint.sourcesChanged {
            return toggleNote
                + "You added or removed a source. Run analysis again so categories and faces include the new library."
        }
        let plural = hint.newPhotoCount == 1 ? "photo was" : "photos were"
        return toggleNote
            + "\(hint.newPhotoCount) new \(plural) indexed since the last analysis. Run again to refresh categories and faces."
    }
}