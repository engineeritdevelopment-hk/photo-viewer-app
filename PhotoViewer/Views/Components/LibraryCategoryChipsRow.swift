import SwiftUI

struct LibraryCategoryChipsRow: View {
    @Bindable var model: LibraryViewModel
    var embedded: Bool = false

    var body: some View {
        if model.detectedCategories.isEmpty {
            EmptyView()
        } else {
            filterLabeledRow("Categories", systemImage: "tag") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.detectedCategories, id: \.title) { category in
                            categoryChip(category)
                        }
                    }
                }
            }
        }
    }

    private func filterLabeledRow<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: embedded ? 100 : nil, alignment: .leading)
            content()
        }
    }

    private func categoryChip(_ category: (title: String, count: Int, rule: SmartAlbumRule)) -> some View {
        let isActive = model.selectedSidebarKey == "semantic:\(category.title)"
        return HStack(spacing: 4) {
            Button {
                model.selectSemanticCategory(category.title)
            } label: {
                HStack(spacing: 4) {
                    Text(category.title)
                        .lineLimit(1)
                    Text("\(category.count)")
                        .foregroundStyle(isActive ? Color.primary.opacity(0.9) : Color.primary.opacity(0.55))
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isActive
                                ? Color.accentColor.opacity(0.32)
                                : Color(nsColor: .windowBackgroundColor)
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isActive ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.16),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .help("Filter by \(category.title)")
        }
        .contextMenu {
            Button("Add to Albums…") {
                model.pinCategoryAsAlbum(category)
            }
            Button("Hide") {
                model.dismissDetectedCategory(category.title)
            }
        }
    }
}