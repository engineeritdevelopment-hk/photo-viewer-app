import SwiftUI

/// Isolates grid cell redraws so toggling one selection does not relayout every thumbnail.
struct PhotoGridCellContainer: View, Equatable {
    let path: String
    let isGridSelected: Bool
    let isInDeleteBin: Bool
    let reportsDragFrames: Bool
    let thumbnailLoader: (String) async -> NSImage?
    let dragPayload: PhotoPathsTransfer
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    static func == (lhs: PhotoGridCellContainer, rhs: PhotoGridCellContainer) -> Bool {
        lhs.path == rhs.path
            && lhs.isGridSelected == rhs.isGridSelected
            && lhs.isInDeleteBin == rhs.isInDeleteBin
            && lhs.reportsDragFrames == rhs.reportsDragFrames
            && lhs.dragPayload == rhs.dragPayload
    }

    var body: some View {
        ThumbnailCell(
            path: path,
            loader: thumbnailLoader,
            isGridSelected: isGridSelected,
            isInDeleteBin: isInDeleteBin
        )
        .photoGridCellFrame(path: path, enabled: reportsDragFrames)
        .draggable(dragPayload) {
            PhotoDragPreview(paths: dragPayload.paths, thumbnail: thumbnailLoader)
        }
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(count: 1, perform: onSingleTap)
    }
}