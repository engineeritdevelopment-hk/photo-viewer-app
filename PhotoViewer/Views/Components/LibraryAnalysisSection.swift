import SwiftUI

/// Analysis options, progress, stale hints, and people — one block.
struct LibraryAnalysisSection: View {
    @Bindable var model: LibraryViewModel
    var showPeopleBar: Bool
    var onShowPeople: () -> Void
    var onHidePeople: () -> Void

    private var showsPeopleHiddenStrip: Bool {
        !showPeopleBar && !model.project.personGroups.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Analysis", systemImage: "sparkles")

            LibraryAnalysisControls(model: model)

            LibraryAnalysisStaleBanner(model: model, embedded: true)
            ActivityBanner(activity: model.activity, embedded: true)

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

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private var panelBackground: Color {
        Color(nsColor: .underPageBackgroundColor).opacity(0.35)
    }
}