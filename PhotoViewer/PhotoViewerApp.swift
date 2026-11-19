import SwiftUI

@main
struct PhotoViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1080, height: 640)
        .windowResizability(.contentMinSize)
    }
}