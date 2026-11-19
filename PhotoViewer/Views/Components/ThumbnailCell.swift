import AppKit
import SwiftUI

struct ThumbnailCell: View {
    let path: String
    let loader: (String) async -> NSImage?
    var isGridSelected: Bool = false
    var isInDeleteBin: Bool = false

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selectionStroke, lineWidth: isGridSelected ? 3 : (isInDeleteBin ? 2 : 0))
            }
            .overlay(alignment: .topTrailing) {
                if isGridSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.body)
                        .padding(4)
                } else if isInDeleteBin {
                    Image(systemName: "trash.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .orange)
                        .font(.caption)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onAppear(perform: startLoad)
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var selectionStroke: Color {
        if isGridSelected { return Color.accentColor }
        if isInDeleteBin { return .orange }
        return .clear
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            let loaded = await loader(path)
            guard !Task.isCancelled else { return }
            image = loaded
            isLoading = false
        }
    }
}