import SwiftUI

struct LibraryActiveFilterBar: View {
    @Bindable var model: LibraryViewModel
    var onReset: () -> Void

    var body: some View {
        if model.isViewFiltered {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Filtered")
                        .font(.subheadline.weight(.semibold))
                    Text(model.viewFilterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Active filters: \(model.viewFilterSummary)")

                HighlightFaceSwitch(model: model)

                Button("Show all", action: onReset)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
        }
    }
}

struct InterfaceBusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
            ProgressView("Working…")
                .controlSize(.large)
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Switch that keeps a frame on the filtered person's face.
struct HighlightFaceSwitch: View {
    @Bindable var model: LibraryViewModel
    var onDarkChrome: Bool = false

    var body: some View {
        if model.filteredPersonId != nil {
            Toggle("Highlight face", isOn: $model.highlightsFilteredFace)
                .toggleStyle(.switch)
                .controlSize(.small)
                .foregroundStyle(onDarkChrome ? Color.white.opacity(0.92) : Color.primary)
                .tint(onDarkChrome ? Color.yellow : Color.accentColor)
                .help("Keep a frame on this person's face while moving between photos")
        }
    }
}