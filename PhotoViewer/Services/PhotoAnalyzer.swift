import Foundation
import UniformTypeIdentifiers

enum PhotoAnalyzer {
    struct Result: Sendable {
        var sceneLabels: [String]
        var ocrSnippet: String?
        var semanticCategory: String
        var suggestedTitle: String?
        var source: AnalysisSource
    }

    static func analyze(url: URL, semanticGroupingOn: Bool, smartTitlesOn: Bool = false) async -> Result {
        let contentType = UTType(filenameExtension: url.pathExtension)
        let snippet = await ContentExtractor.extract(from: url, contentType: contentType)
        let isScreenshot = SmartAnalyzer.isScreenshot(at: url)
        let instant = SmartAnalyzer.instantPass(url: url, contentType: contentType, isDirectory: false)

        var semantic = instant.typeFolder
        var suggestedTitle: String?
        var source: AnalysisSource = snippet == nil ? .metadata : .ocrAndNLP

        if semanticGroupingOn {
            let text = [snippet, url.lastPathComponent].compactMap { $0 }.joined(separator: " ")
            if isScreenshot {
                semantic = "Screenshots"
            } else if let snippet {
                semantic = nlpSemanticFallback(text: text, isScreenshot: isScreenshot)
                source = .ocrAndNLP
            }
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if semanticGroupingOn,
               let ai = await FoundationModelsAnalysis.suggest(
                fileName: url.lastPathComponent,
                snippet: snippet,
                category: instant.category
               ) {
                semantic = ai.semanticFolder
                if smartTitlesOn {
                    let title = ai.descriptiveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    suggestedTitle = title.isEmpty ? nil : title
                }
                source = .onDeviceAI
            }
        }
        #endif

        let sceneLabels = sceneLabelsFromSnippet(snippet)
        return Result(
            sceneLabels: sceneLabels,
            ocrSnippet: snippet,
            semanticCategory: semantic,
            suggestedTitle: suggestedTitle,
            source: source
        )
    }

    private static func nlpSemanticFallback(text: String, isScreenshot: Bool) -> String {
        if isScreenshot { return "Screenshots" }
        if let visionCategory = semanticCategoryFromVisionSnippet(text) {
            return visionCategory
        }
        if let matched = SemanticFolders.matchCategory(in: text) {
            return matched
        }
        return SemanticFolders.defaultFolder
    }

    /// Map Vision `VNClassifyImageRequest` labels (from `Image: …` snippets) without treating the word "image" as Media.
    private static func semanticCategoryFromVisionSnippet(_ text: String) -> String? {
        let marker = "image: "
        guard text.lowercased().hasPrefix(marker) else { return nil }
        let labels = String(text.dropFirst(marker.count)).lowercased()
        for (folder, keywords) in SemanticFolders.anchors {
            if keywords.contains(where: { labels.contains($0) }) {
                return folder
            }
        }
        return nil
    }

    private static func sceneLabelsFromSnippet(_ snippet: String?) -> [String] {
        guard let snippet, snippet.hasPrefix("Image: ") else { return [] }
        return snippet
            .replacingOccurrences(of: "Image: ", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}