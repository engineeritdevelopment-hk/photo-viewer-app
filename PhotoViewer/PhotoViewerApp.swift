import SwiftUI

@main
struct PhotoViewerApp: App {
    @State private var appUpdate = AppUpdateModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appUpdate)
                .appUpdateAlerts(using: appUpdate)
        }
        .defaultSize(width: 1080, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await appUpdate.checkForUpdates(userInitiated: true) }
                }
                .disabled(appUpdate.isChecking)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}