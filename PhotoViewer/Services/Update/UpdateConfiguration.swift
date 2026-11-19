import Foundation

enum UpdateConfiguration {
  /// Default repository for release checks (`owner/name`). Override via Info.plist `PhotoViewerGitHubRepository`.
  private static let defaultRepository = "engineeritdevelopment-hk/photo-viewer-app"

  static var githubRepository: String {
    if let custom = Bundle.main.object(forInfoDictionaryKey: "PhotoViewerGitHubRepository") as? String {
      let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return defaultRepository
  }

  static var automaticCheckInterval: TimeInterval { 24 * 60 * 60 }
}