import SwiftUI

struct AppUpdateAlertsModifier: ViewModifier {
  @Bindable var updates: AppUpdateModel

  func body(content: Content) -> some View {
    content
      .task {
        await updates.performAutomaticCheckIfNeeded()
      }
      .alert(
        "Update Available",
        isPresented: Binding(
          get: { updates.offerToPresent != nil },
          set: { if !$0 { updates.offerToPresent = nil } }
        ),
        presenting: updates.offerToPresent
      ) { offer in
        Button("Download from GitHub") {
          updates.openReleasePage(for: offer)
        }
        Button("Not Now", role: .cancel) {
          updates.dismissOffer(offer)
        }
      } message: { offer in
        Text(updateMessage(for: offer))
      }
      .alert(item: $updates.manualCheckAlert) { alert in
        Alert(
          title: Text(alert.title),
          message: Text(alert.message),
          dismissButton: .default(Text("OK"))
        )
      }
  }

  private func updateMessage(for offer: ReleaseUpdateOffer) -> String {
    var lines = ["A newer version (\(offer.versionLabel)) is available."]
    if !offer.releaseNotes.isEmpty {
      let snippet = String(offer.releaseNotes.prefix(400))
      lines.append(snippet)
      if offer.releaseNotes.count > 400 {
        lines.append("…")
      }
    }
    lines.append("Open the release page to download.")
    return lines.joined(separator: "\n\n")
  }
}

extension View {
  func appUpdateAlerts(using updates: AppUpdateModel) -> some View {
    modifier(AppUpdateAlertsModifier(updates: updates))
  }
}