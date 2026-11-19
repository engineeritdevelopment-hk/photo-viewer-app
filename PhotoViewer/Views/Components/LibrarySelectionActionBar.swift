import SwiftUI

struct LibrarySelectionActionBar: View {
    @Bindable var model: LibraryViewModel
    var onAddToNewAlbum: () -> Void

    private var count: Int { model.selectedPaths.count }

    private var favoriteTitle: String {
        model.selectedPaths.allSatisfy { model.isFavorite(path: $0) } ? "Unfavorite" : "Favorite"
    }

    private var favoriteIcon: String {
        model.selectedPaths.allSatisfy { model.isFavorite(path: $0) } ? "star.slash" : "star"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 24)

            actionButton(favoriteTitle, systemImage: favoriteIcon) {
                model.toggleFavoriteSelectedPhotos()
            }

            Menu {
                ForEach(manualAlbums) { album in
                    Button("Add to \(album.name)") {
                        model.addPathsToAlbum(albumId: album.id, paths: Array(model.selectedPaths))
                    }
                }
                if !manualAlbums.isEmpty { Divider() }
                Button("New album…") {
                    onAddToNewAlbum()
                }
            } label: {
                actionLabel("Album", systemImage: "rectangle.stack.badge.plus")
            }
            .menuStyle(.borderlessButton)

            actionButton("Delete bin", systemImage: "trash") {
                model.addSelectedToDeleteBin()
            }

            Spacer(minLength: 8)

            actionButton("Select all", systemImage: "checkmark.circle") {
                model.selectAllVisiblePhotos()
            }

            actionButton("Clear", systemImage: "xmark") {
                model.clearGridSelection()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }

    private var manualAlbums: [Album] {
        model.project.albums.filter { $0.kind == .manual && !$0.isFavorites }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: Capsule(style: .continuous))
    }
}