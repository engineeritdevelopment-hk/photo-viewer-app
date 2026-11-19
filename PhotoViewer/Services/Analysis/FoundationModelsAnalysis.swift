import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct FileAnalysisSuggestion {
    @Guide(description: "Semantic folder name such as Finance & Receipts or Screenshots")
    var semanticFolder: String

    @Guide(description: "Short descriptive title without file extension")
    var descriptiveTitle: String
}

@available(macOS 26.0, *)
enum FoundationModelsAnalysis {
    static func suggest(fileName: String, snippet: String?, category: String) async -> FileAnalysisSuggestion? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let session = LanguageModelSession()
        let snippetText = snippet ?? "(no text extracted)"
        let prompt = """
        Organize this file into a semantic folder and suggest a clean title.
        File name: \(fileName)
        Detected category: \(category)
        Content preview: \(snippetText.prefix(400))
        Use folder names like: Food, Finance & Receipts, Work & Projects, Travel & Tickets, Study & Notes, Screenshots, Media, Documents, Archives, Code, Other.
        Title should be concise, no extension.
        """

        do {
            let response = try await session.respond(to: prompt, generating: FileAnalysisSuggestion.self)
            return response.content
        } catch {
            return nil
        }
    }
}
#endif