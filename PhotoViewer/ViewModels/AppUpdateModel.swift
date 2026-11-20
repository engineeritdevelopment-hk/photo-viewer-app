import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppUpdateModel {
  private let checker: ReleaseUpdateChecker

  init(updateChecker: ReleaseUpdateChecker = ReleaseUpdateChecker()) {
    checker = updateChecker
  }
  private let downloader = AppUpdateDownloader()

  var isChecking = false
  var offerToPresent: ReleaseUpdateOffer?
  /// Versions the user chose “Later” for during this process (prompt again next launch).
  private var skippedThisSession = Set<String>()

  var installPhase: InstallPhase = .idle
  var downloadProgress: Double = 0

  enum InstallPhase: Equatable {
    case idle
    case downloading
    case installing
    case failed(String)
  }

  /// Shown after a manual “Check for Updates”.
  var manualCheckAlert: ManualCheckAlert?

  struct ManualCheckAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  func performCheckOnLaunch() async {
    defer { AppPreferences.recordAutomaticUpdateCheck() }
    await checkForUpdates(userInitiated: false)
  }

  /// If the app stays open across days, check again at most once per interval.
  func performPeriodicCheckIfNeeded() async {
    guard AppPreferences.shouldRunAutomaticUpdateCheck() else { return }
    defer { AppPreferences.recordAutomaticUpdateCheck() }
    await checkForUpdates(userInitiated: false)
  }

  func checkForUpdates(userInitiated: Bool) async {
    guard !isChecking, installPhase == .idle else { return }
    isChecking = true
    defer { isChecking = false }

    do {
      let offer = try await checker.latestRelease(repository: UpdateConfiguration.githubRepository)
      guard let current = AppVersion.current() else {
        if userInitiated {
          manualCheckAlert = ManualCheckAlert(
            title: "Check for Updates",
            message: "This build does not report an app version."
          )
        }
        return
      }

      if offer.version > current {
        if !userInitiated, skippedThisSession.contains(offer.versionLabel) {
          return
        }
        offerToPresent = offer
        return
      }

      if userInitiated {
        manualCheckAlert = ManualCheckAlert(
          title: "Check for Updates",
          message: "Photo Viewer \(current.displayString) is up to date."
        )
      }
    } catch {
      if userInitiated {
        manualCheckAlert = ManualCheckAlert(
          title: "Check for Updates",
          message: error.localizedDescription
        )
      }
    }
  }

  func remindLater(offer: ReleaseUpdateOffer) {
    skippedThisSession.insert(offer.versionLabel)
    offerToPresent = nil
  }

  func startAutomaticInstall(offer: ReleaseUpdateOffer) async {
    guard let downloadURL = offer.downloadURL else {
      installPhase = .failed(
        "This release has no .zip installer. Open the release page to download manually."
      )
      return
    }

    installPhase = .downloading
    downloadProgress = 0

    do {
      let zipURL = try await downloader.download(
        from: downloadURL,
        into: ApplicationPaths.updateDownloads
      ) { [weak self] fraction in
        self?.downloadProgress = fraction
      }
      installPhase = .installing
      try AppUpdateInstaller.install(zipURL: zipURL)
    } catch {
      installPhase = .failed(error.localizedDescription)
    }
  }

  func openReleasePage(for offer: ReleaseUpdateOffer) {
    NSWorkspace.shared.open(offer.releasePageURL)
  }
}