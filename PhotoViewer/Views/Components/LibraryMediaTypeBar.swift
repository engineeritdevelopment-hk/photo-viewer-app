import SwiftUI

struct LibraryMediaTypeBar: View {
    @Bindable var model: LibraryViewModel
    var embedded: Bool = false

    var body: some View {
        if model.detectedMediaExtensions.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: 8) {
                if embedded {
                    Label("Types", systemImage: "doc.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .frame(width: 100, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        Text("Media types")
                            .font(.caption.weight(.semibold))
                        if model.isMediaTypeFilterActive {
                            Text("filtered")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.detectedMediaExtensions, id: \.ext) { item in
                            MediaTypeBadge(
                                ext: item.ext,
                                count: item.count,
                                isSelected: model.selectedMediaExtensions.contains(item.ext)
                            ) {
                                model.toggleMediaType(item.ext)
                            }
                        }
                    }
                }

                if model.isMediaTypeFilterActive {
                    Button("All") { model.selectAllMediaTypes() }
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, embedded ? 0 : 12)
            .padding(.vertical, embedded ? 0 : 4)
            .background {
                if !embedded {
                    Color(nsColor: .underPageBackgroundColor).opacity(0.35)
                }
            }
            .overlay(alignment: .bottom) {
                if !embedded { Divider() }
            }
        }
    }
}

private struct MediaTypeBadge: View {
    let ext: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(extLabel)
                    .font(.caption2.weight(.semibold))
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Click to hide \(extLabel) from the grid" : "Click to show \(extLabel) in the grid")
    }

    private var extLabel: String {
        ext.uppercased()
    }
}