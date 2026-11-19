import AppKit
import Foundation

enum FaceThumbnailWriter {
    static func save(cgImage: CGImage, groupId: String) -> String? {
        let url = ApplicationPaths.faceCrop(groupId: groupId)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }
}