import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PhotoPathsTransfer: Codable, Transferable, Hashable {
    let paths: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct PhotoDragPreview: View {
    let paths: [String]
    let thumbnail: (String) async -> NSImage?

    @State private var previewImage: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }

            if paths.count > 1 {
                Text("\(paths.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .offset(x: 6, y: 6)
            }
        }
        .padding(6)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 8, y: 4)
        .task(id: paths.first) {
            guard let first = paths.first else { return }
            previewImage = await thumbnail(first)
        }
    }
}

@MainActor
enum PhotoAlbumDragDrop {
    static func payload(for path: String, model: LibraryViewModel) -> PhotoPathsTransfer {
        if !model.selectedPaths.isEmpty,
           model.selectedPaths.contains(path)
        {
            return PhotoPathsTransfer(paths: model.selectedPaths.sorted())
        }
        if !model.selectedPaths.isEmpty, !model.selectedPaths.contains(path) {
            return PhotoPathsTransfer(paths: [path])
        }
        return PhotoPathsTransfer(paths: [path])
    }
}

struct PhotoPathsDropRowModifier: ViewModifier {
    let acceptsDrop: Bool
    var highlight: Color = Color.accentColor.opacity(0.25)
    let onDrop: ([String]) -> Bool

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background {
                if isTargeted, acceptsDrop {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(highlight)
                }
            }
            .dropDestination(for: PhotoPathsTransfer.self) { items, _ in
                guard acceptsDrop, let transfer = items.first else { return false }
                return onDrop(transfer.paths)
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

extension View {
    func albumPhotoDropDestination(
        acceptsDrop: Bool,
        onDrop: @escaping ([String]) -> Bool
    ) -> some View {
        photoPathsDropDestination(acceptsDrop: acceptsDrop, onDrop: onDrop)
    }

    func photoPathsDropDestination(
        acceptsDrop: Bool,
        highlight: Color = Color.accentColor.opacity(0.25),
        onDrop: @escaping ([String]) -> Bool
    ) -> some View {
        modifier(PhotoPathsDropRowModifier(acceptsDrop: acceptsDrop, highlight: highlight, onDrop: onDrop))
    }
}