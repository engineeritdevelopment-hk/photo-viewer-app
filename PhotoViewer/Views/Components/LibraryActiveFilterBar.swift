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

                Button("Show all", action: onReset)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Active filters: \(model.viewFilterSummary)")
            .accessibilityHint("Double-tap Show all to clear filters")
        }
    }
}