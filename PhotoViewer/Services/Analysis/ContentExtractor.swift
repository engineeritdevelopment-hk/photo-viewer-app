import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
import AppKit

enum ContentExtractor {
    private static let maxSnippetLength = 600
    private static let maxTextReadBytes = 1024

    static func extract(from url: URL, contentType: UTType?) async -> String? {
        await Task.detached(priority: .utility) {
            extractSync(from: url, contentType: contentType)
        }.value
    }

    private static func extractSync(from url: URL, contentType: UTType?) -> String? {
        let type = contentType ?? UTType(filenameExtension: url.pathExtension)

        if type?.conforms(to: .pdf) == true {
            return extractPDF(from: url)
        }

        if type?.conforms(to: .image) == true {
            return extractImage(from: url)
        }

        if isPlainTextLike(type) {
            return readTextPrefix(from: url)
        }

        return nil
    }

    private static func isPlainTextLike(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .plainText)
            || type.conforms(to: .sourceCode)
            || type.conforms(to: .json)
            || type.identifier == "net.daringfireball.markdown"
            || type.identifier == "public.markdown"
    }

    private static func extractPDF(from url: URL) -> String? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0),
              let text = page.string
        else { return nil }
        return truncate(text)
    }

    private static func extractImage(from url: URL) -> String? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        if let ocr = runOCR(on: cgImage, level: .fast), !ocr.isEmpty {
            return truncate(ocr)
        }
        if let ocr = runOCR(on: cgImage, level: .accurate), !ocr.isEmpty {
            return truncate(ocr)
        }
        return classifyImage(cgImage)
    }

    private static func runOCR(on cgImage: CGImage, level: VNRequestTextRecognitionLevel) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        } catch {
            return nil
        }
    }

    private static func classifyImage(_ cgImage: CGImage) -> String? {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let labels = (request.results ?? [])
                .prefix(3)
                .compactMap { $0.identifier }
            guard !labels.isEmpty else { return nil }
            return "Image: " + labels.joined(separator: ", ")
        } catch {
            return nil
        }
    }

    private static func readTextPrefix(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxTextReadBytes) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
        return truncate(text)
    }

    private static func truncate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxSnippetLength {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxSnippetLength)
        return String(trimmed[..<end])
    }
}