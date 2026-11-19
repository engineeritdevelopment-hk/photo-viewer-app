import Foundation

enum ReleaseUpdateError: LocalizedError {
  case invalidRepository
  case invalidResponse
  case unparsableVersion(String)
  case noRelease

  var errorDescription: String? {
    switch self {
    case .invalidRepository:
      return "Update checking is not configured for this build."
    case .invalidResponse:
      return "Could not read release information from GitHub."
    case .unparsableVersion(let tag):
      return "The latest release tag “\(tag)” is not a valid version."
    case .noRelease:
      return "No published release was found."
    }
  }
}

actor ReleaseUpdateChecker {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func latestRelease(repository: String) async throws -> ReleaseUpdateOffer {
    let trimmed = repository.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("/") else { throw ReleaseUpdateError.invalidRepository }

    let url = URL(string: "https://api.github.com/repos/\(trimmed)/releases/latest")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("PhotoViewer-UpdateCheck", forHTTPHeaderField: "User-Agent")
    if let version = AppVersion.current()?.displayString {
      request.setValue("PhotoViewer/\(version)", forHTTPHeaderField: "User-Agent")
    }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
      throw ReleaseUpdateError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
    if decoded.draft == true || decoded.prerelease == true {
      throw ReleaseUpdateError.noRelease
    }

    guard let version = AppVersion.parse(decoded.tag_name) else {
      throw ReleaseUpdateError.unparsableVersion(decoded.tag_name)
    }

    let title = decoded.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? decoded.tag_name
    let notes = decoded.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let downloadURL = ReleaseAssetPicker.preferredZipURL(from: decoded.assets ?? [])

    return ReleaseUpdateOffer(
      version: version,
      versionLabel: decoded.tag_name,
      title: title,
      releaseNotes: notes,
      releasePageURL: decoded.html_url,
      downloadURL: downloadURL
    )
  }
}

private struct GitHubRelease: Decodable {
  let tag_name: String
  let html_url: URL
  let name: String?
  let body: String?
  let draft: Bool?
  let prerelease: Bool?
  let assets: [GitHubReleaseAsset]?
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}