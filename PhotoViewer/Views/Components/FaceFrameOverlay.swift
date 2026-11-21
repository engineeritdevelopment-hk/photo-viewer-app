import SwiftUI

/// Draw or tap a face on a fitted photo. Rectangles are in the view, then converted to the image.
struct FaceFrameOverlay: View {
    let imageSize: CGSize
    let faces: [FaceAlignment.AlignedFace]
    var names: [UUID: String] = [:]
    var allowsInteraction = true
    var onSelect: (FaceAlignment.AlignedFace) -> Void
    var onFrame: (CGRect) -> Void

    @State private var dragRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            let fitted = aspectFit(geo.size, imageSize)
            ZStack {
                Color.black.opacity(allowsInteraction ? 0.001 : 0)
                ForEach(faces) { face in
                    let rect = map(face.normalizedRect, into: fitted)
                    faceBox(face)
                        .frame(width: max(rect.width, 24), height: max(rect.height, 24))
                        .position(x: rect.midX, y: rect.midY)
                        .help(help(for: face))
                }
                if let dragRect {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(Color.white.opacity(0.12))
                        .frame(width: dragRect.width, height: dragRect.height)
                        .position(x: dragRect.midX, y: dragRect.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .allowsHitTesting(allowsInteraction)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard allowsInteraction else { return }
                        dragRect = box(from: value.startLocation, to: value.location)
                    }
                    .onEnded { value in
                        guard allowsInteraction else { return }
                        let drawn = box(from: value.startLocation, to: value.location)
                        dragRect = nil
                        let normalized = unmap(drawn, from: fitted)
                        guard normalized.width > 0.02, normalized.height > 0.02 else { return }
                        onFrame(normalized)
                    }
            )
        }
        .allowsHitTesting(allowsInteraction)
    }

    @ViewBuilder
    private func faceBox(_ face: FaceAlignment.AlignedFace) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Color.yellow, lineWidth: 2)
            .background(Color.yellow.opacity(0.12))
            .overlay(alignment: .bottom) {
                if let name = names[face.id] {
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.72), in: Capsule())
                        .fixedSize()
                        .offset(y: 16)
                }
            }
        if allowsInteraction {
            Button {
                onSelect(face)
            } label: {
                shape
            }
            .buttonStyle(.plain)
        } else {
            shape
        }
    }

    private func help(for face: FaceAlignment.AlignedFace) -> String {
        let pose = face.yaw <= FaceAlignment.frontalYawLimit ? "Face looking at the camera" : "Side face"
        if let name = names[face.id] {
            return "\(name). \(pose)"
        }
        return pose
    }

    private func aspectFit(_ view: CGSize, _ image: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, view.width > 0, view.height > 0 else {
            return CGRect(origin: .zero, size: view)
        }
        let scale = min(view.width / image.width, view.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (view.width - size.width) / 2,
            y: (view.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func map(_ normalized: CGRect, into fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + normalized.origin.x * fitted.width,
            y: fitted.minY + normalized.origin.y * fitted.height,
            width: normalized.width * fitted.width,
            height: normalized.height * fitted.height
        )
    }

    private func unmap(_ viewRect: CGRect, from fitted: CGRect) -> CGRect {
        guard fitted.width > 1, fitted.height > 1 else { return .zero }
        let clipped = viewRect.intersection(fitted)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return .zero }
        return CGRect(
            x: (clipped.minX - fitted.minX) / fitted.width,
            y: (clipped.minY - fitted.minY) / fitted.height,
            width: clipped.width / fitted.width,
            height: clipped.height / fitted.height
        )
    }

    private func box(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
