import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppUpdateModel {
  private let checker = ReleaseUpdateChecker()

  var isChecking = false
  var offerToPresent: ReleaseUpdateOffer?
  /// Shown after a manual “Check for Updates”.
  var manualCheckAlert: ManualCheckAlert?

  struct ManualCheckAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  func performAutomaticCheckIfNeeded() async {
    guard AppPreferences.shouldRunAutomaticUpdateCheck() else { return }
    defer { AppPreferences.recordAutomaticUpdateCheck() }
    await checkForUpdates(userInitiated: false)
  }

  func checkForUpdates(userInitiated: Bool) async {
    guard !isChecking else { return }
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
        guard !AppPreferences.isUpdateDismissed(label: offer.versionLabel) else {
          if userInitiated {
            manualCheckAlert = ManualCheckAlert(
              title: "Check for Updates",
              message: "Version \(offer.versionLabel) is available. You chose not to be reminded for this release."
            )
          }
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

  func dismissOffer(_ offer: ReleaseUpdateOffer) {
    AppPreferences.dismissUpdate(label: offer.versionLabel)
    if offerToPresent == offer {
      offerToPresent = nil
    }
  }

  func openReleasePage(for offer: ReleaseUpdateOffer) {
    NSWorkspace.shared.open(offer.releasePageURL)
    offerToPresent = nil
  }
}