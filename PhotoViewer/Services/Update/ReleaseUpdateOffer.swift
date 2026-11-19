import Foundation

struct ReleaseUpdateOffer: Equatable, Sendable {
  let version: AppVersion
  /// Tag or version string as published (e.g. `v1.2.0`).
  let versionLabel: String
  let title: String
  let releaseNotes: String
  let releasePageURL: URL
  /// Zip asset from the GitHub release (auto-install).
  let downloadURL: URL?
}