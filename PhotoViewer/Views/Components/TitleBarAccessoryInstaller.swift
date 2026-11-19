import AppKit
import ObjectiveC
import SwiftUI

/// About control only — title is `NSWindow.title` so the system does not group both in one capsule.
struct AppTitlebarLeadingContent: View {
    @Bindable var appUpdate: AppUpdateModel

    var body: some View {
        AppInfoButton(appUpdate: appUpdate, style: .titlebar)
            .fixedSize()
    }
}

private enum TitlebarAccessoryAnchor {
    private static let controllerKey = "com.photoviewer.titlebarAccessory"
    private static let controllerMarkerKey = "com.photoviewer.titlebarAccessory.marker"

    static func controller(for window: NSWindow) -> NSTitlebarAccessoryViewController? {
        objc_getAssociatedObject(window, controllerKey) as? NSTitlebarAccessoryViewController
    }

    static func markAsPhotoViewerLeading(_ controller: NSTitlebarAccessoryViewController) {
        objc_setAssociatedObject(controller, controllerMarkerKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func isPhotoViewerLeading(_ controller: NSTitlebarAccessoryViewController) -> Bool {
        objc_getAssociatedObject(controller, controllerMarkerKey) as? Bool == true
    }

    static func store(_ controller: NSTitlebarAccessoryViewController, on window: NSWindow) {
        objc_setAssociatedObject(window, controllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        markAsPhotoViewerLeading(controller)
    }

    static func removeInstalledAccessories(from window: NSWindow) {
        let accessories = window.titlebarAccessoryViewControllers
        for index in accessories.indices.reversed() where isPhotoViewerLeading(accessories[index]) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        objc_setAssociatedObject(window, controllerKey, nil, .OBJC_ASSOCIATION_ASSIGN)
    }
}

struct TitlebarLeadingAccessoryInstaller: NSViewRepresentable {
    let appUpdate: AppUpdateModel

    func makeCoordinator() -> Coordinator {
        Coordinator(appUpdate: appUpdate)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.appUpdate = appUpdate
        context.coordinator.refreshHostingContent()
    }

    final class Coordinator {
        var appUpdate: AppUpdateModel
        weak var hostingView: NSHostingView<AnyView>?
        private weak var installedWindow: NSWindow?

        init(appUpdate: AppUpdateModel) {
            self.appUpdate = appUpdate
        }

        func refreshHostingContent() {
            hostingView?.rootView = AnyView(
                AppTitlebarLeadingContent(appUpdate: appUpdate)
            )
        }

        func installWhenAttached(to view: NSView) {
            guard let window = view.window else { return }

            if installedWindow === window, TitlebarAccessoryAnchor.controller(for: window) != nil {
                refreshHostingContent()
                return
            }

            TitlebarAccessoryAnchor.removeInstalledAccessories(from: window)

            let hosting = NSHostingView(
                rootView: AnyView(AppTitlebarLeadingContent(appUpdate: appUpdate))
            )
            configureTransparentTitlebarHosting(hosting)

            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .leading
            controller.view = hosting
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            let height = max(22, size.height)
            let width = max(24, size.width)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            controller.view.frame = hosting.frame

            window.title = "Photo Viewer"
            window.titleVisibility = .hidden
            window.addTitlebarAccessoryViewController(controller)

            TitlebarAccessoryAnchor.store(controller, on: window)
            hostingView = hosting
            installedWindow = window
        }
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let coordinator = self.coordinator else { return }
                coordinator.installWhenAttached(to: self)
            }
        }
    }
}

private func configureTransparentTitlebarHosting<Content: View>(_ hosting: NSHostingView<Content>) {
    hosting.wantsLayer = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
}

extension View {
    func installTitlebarLeadingAccessory(appUpdate: AppUpdateModel) -> some View {
        background {
            TitlebarLeadingAccessoryInstaller(appUpdate: appUpdate)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }
}