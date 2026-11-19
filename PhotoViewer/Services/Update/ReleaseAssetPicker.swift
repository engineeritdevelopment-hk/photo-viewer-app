import Foundation

enum ReleaseAssetPicker {
  static func preferredZipURL(from assets: [GitHubReleaseAsset]) -> URL? {
    let zipAssets = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
    guard !zipAssets.isEmpty else { return nil }

    let ranked = zipAssets.sorted { lhs, rhs in
      score(lhs.name) > score(rhs.name)
    }
    return ranked.first?.browser_download_url
  }

  private static func score(_ name: String) -> Int {
    let lower = name.lowercased()
    var value = 0
    if lower.contains("photo") { value += 4 }
    if lower.contains("viewer") { value += 4 }
    if lower.contains("mac") { value += 1 }
    return value
  }
}

struct GitHubReleaseAsset: Decodable, Sendable {
  let name: String
  let browser_download_url: URL
}