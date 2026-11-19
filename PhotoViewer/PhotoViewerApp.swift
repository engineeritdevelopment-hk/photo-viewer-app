import SwiftUI

@main
struct PhotoViewerApp: App {
    @State private var appUpdate = AppUpdateModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appUpdate)
                .appUpdateAlerts(using: appUpdate)
                .installTitlebarLeadingAccessory(appUpdate: appUpdate)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .defaultSize(width: 1080, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Photo Viewer") {
                    appUpdate.manualCheckAlert = AppUpdateModel.ManualCheckAlert(
                        title: "Photo Viewer",
                        message: aboutMessage()
                    )
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await appUpdate.checkForUpdates(userInitiated: true) }
                }
                .disabled(appUpdate.isChecking)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }

    private func aboutMessage() -> String {
        let version = AppVersion.current()?.displayString ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (build \(build)). Use Check for Updates for new releases."
    }
}