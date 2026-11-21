import SwiftUI

struct AppUpdateSheet: View {
  let offer: ReleaseUpdateOffer
  @Bindable var updates: AppUpdateModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 28))
          .foregroundStyle(Color.accentColor)
          .symbolRenderingMode(.hierarchical)
        VStack(alignment: .leading, spacing: 2) {
          Text("Update Available")
            .font(.title2.bold())
          Text(offer.versionLabel)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      if !offer.releaseNotes.isEmpty {
        ScrollView {
          Text(offer.releaseNotes)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer(minLength: 0)
      }

      installStatusView

      HStack {
        Button("Later") {
          updates.remindLater(offer: offer)
        }
        .disabled(isBusy)

        Spacer()

        if offer.downloadURL == nil {
          Button("Open Release Page") {
            updates.openReleasePage(for: offer)
          }
        } else {
          Button(installButtonTitle) {
            Task { await updates.startAutomaticInstall(offer: offer) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isBusy)
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(24)
    .frame(width: 460, height: 560)
  }

  private var isBusy: Bool {
    switch updates.installPhase {
    case .downloading, .installing:
      return true
    default:
      return false
    }
  }

  private var installButtonTitle: String {
    switch updates.installPhase {
    case .downloading, .installing:
      return "Updating…"
    default:
      return "Update"
    }
  }

  @ViewBuilder
  private var installStatusView: some View {
    switch updates.installPhase {
    case .idle:
      Text("Photo Viewer will download the update in the background, replace itself, and reopen.")
        .font(.callout)
        .foregroundStyle(.secondary)
    case .downloading:
      VStack(alignment: .leading, spacing: 8) {
        ProgressView(value: updates.downloadProgress)
        Text("Downloading… \(Int(updates.downloadProgress * 100))%")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    case .installing:
      HStack(spacing: 10) {
        ProgressView()
        Text("Installing and relaunching…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    case .failed(let message):
      Text(message)
        .font(.callout)
        .foregroundStyle(.orange)
    }
  }
}