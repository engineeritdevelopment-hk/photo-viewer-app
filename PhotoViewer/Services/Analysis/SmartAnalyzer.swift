import CoreServices
import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

enum SmartAnalyzer {
    static func isScreenshot(at url: URL) -> Bool {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return false }
        guard let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) else { return false }
        if let boolean = value as? Bool { return boolean }
        return (value as? NSNumber)?.boolValue == true
    }

    static func instantPass(
        url: URL,
        contentType: UTType?,
        isDirectory: Bool
    ) -> (category: String, typeFolder: String) {
        if isDirectory {
            return ("Folders", "Folders")
        }

        if isScreenshot(at: url) {
            return ("Screenshots", "Images")
        }

        let type = contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        return (category(for: type), typeFolder(for: type))
    }

    private static func category(for type: UTType) -> String {
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .audiovisualContent) || type.conforms(to: .movie) || type.conforms(to: .audio) {
            return "Media"
        }
        if type.conforms(to: .archive) { return "Archives" }
        if type.conforms(to: .sourceCode) { return "Code" }
        if type.identifier == "com.apple.disk-image" || type.identifier == "com.apple.package" {
            return "Installers"
        }
        if type.conforms(to: .pdf) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .presentation) || type.conforms(to: .rtf)
            || type.conforms(to: .plainText) {
            return "Documents"
        }
        return "Other"
    }

    private static func typeFolder(for type: UTType) -> String {
        category(for: type)
    }
}