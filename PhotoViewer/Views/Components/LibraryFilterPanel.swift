import SwiftUI

/// Grid filters: file type, date range, detected categories.
struct LibraryFilterPanel: View {
    @Bindable var model: LibraryViewModel

    private var hasContent: Bool {
        !model.detectedMediaExtensions.isEmpty
            || !model.detectedCategories.isEmpty
            || true
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Filters", systemImage: "line.3.horizontal.decrease.circle")

                LibraryMediaTypeBar(model: model, embedded: true)
                LibraryFilterBar(model: model, embedded: true)
                LibraryCategoryChipsRow(model: model, embedded: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBackground)
            .overlay(alignment: .bottom) { Divider() }
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