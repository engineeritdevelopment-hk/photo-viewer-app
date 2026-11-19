import SwiftUI

// MARK: - Cell frame reporting

private struct PhotoGridCellFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func photoGridCellFrame(path: String, coordinateSpace: String = "photoGrid", enabled: Bool = true) -> some View {
        background {
            if enabled {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PhotoGridCellFramesKey.self,
                        value: [path: geometry.frame(in: .named(coordinateSpace))]
                    )
                }
            }
        }
    }
}

// MARK: - Drag stroke hit testing

enum PhotoGridDragSelection {
  /// Samples a segment so fast drags still hit cells between events.
    static func paths(
        alongStrokeFrom start: CGPoint,
        to end: CGPoint,
        cellFrames: [String: CGRect],
        step: CGFloat = 14
    ) -> [String] {
        var hits: Set<String> = []
        for point in samplePoints(from: start, to: end, step: step) {
            for (path, frame) in cellFrames where frame.contains(point) {
                hits.insert(path)
            }
        }
        return Array(hits)
    }

    static func samplePoints(from start: CGPoint, to end: CGPoint, step: CGFloat) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.5 else { return [end] }
        let count = max(1, Int(ceil(distance / step)))
        return (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return CGPoint(x: start.x + dx * t, y: start.y + dy * t)
        }
    }
}

// MARK: - Gesture modifier

struct PhotoGridDragSelectGesture: ViewModifier {
    @Bindable var model: LibraryViewModel
    let cellFrames: [String: CGRect]
    @Binding var strokeTouched: Set<String>
    @Binding var lastDragPoint: CGPoint?
    @Binding var isDragSelecting: Bool

    func body(content: Content) -> some View {
        content.simultaneousGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("photoGrid"))
            .onChanged { value in
                if !isDragSelecting {
                    isDragSelecting = true
                }
                let from = lastDragPoint ?? value.startLocation
                let paths = PhotoGridDragSelection.paths(
                    alongStrokeFrom: from,
                    to: value.location,
                    cellFrames: cellFrames
                )
                for path in paths where !strokeTouched.contains(path) {
                    strokeTouched.insert(path)
                    model.selectGridPhoto(path: path)
                }
                lastDragPoint = value.location
            }
            .onEnded { _ in
                strokeTouched.removeAll()
                lastDragPoint = nil
                isDragSelecting = false
            }
    }
}

extension View {
    func photoGridDragSelect(
        model: LibraryViewModel,
        cellFrames: [String: CGRect],
        strokeTouched: Binding<Set<String>>,
        lastDragPoint: Binding<CGPoint?>,
        isDragSelecting: Binding<Bool>
    ) -> some View {
        modifier(PhotoGridDragSelectGesture(
            model: model,
            cellFrames: cellFrames,
            strokeTouched: strokeTouched,
            lastDragPoint: lastDragPoint,
            isDragSelecting: isDragSelecting
        ))
    }

    func onPhotoGridCellFramesChange(_ handler: @escaping ([String: CGRect]) -> Void) -> some View {
        onPreferenceChange(PhotoGridCellFramesKey.self, perform: handler)
    }
}