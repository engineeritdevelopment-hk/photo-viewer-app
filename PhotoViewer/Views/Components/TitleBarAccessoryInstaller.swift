import AppKit
import ObjectiveC
import SwiftUI

/// Info control sitting on the trailing side of the centered window title.
struct TitlebarInfoButtonInstaller: NSViewRepresentable {
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
        context.coordinator.attach(from: nsView)
    }

    final class Coordinator {
        var appUpdate: AppUpdateModel
        private let hosting: NSHostingView<AnyView>
        private weak var installedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(appUpdate: AppUpdateModel) {
            self.appUpdate = appUpdate
            hosting = NSHostingView(rootView: AnyView(AppTitlebarInfoButton(appUpdate: appUpdate)))
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            hosting.translatesAutoresizingMaskIntoConstraints = true
        }

        func refreshHostingContent() {
            hosting.rootView = AnyView(AppTitlebarInfoButton(appUpdate: appUpdate))
        }

        func attach(from view: NSView) {
            guard let window = view.window else { return }
            window.title = "Photo Viewer"
            window.titleVisibility = .visible
            removeLegacyAccessories(from: window)

            if installedWindow !== window {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers.removeAll()
                let center = NotificationCenter.default
                observers.append(center.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reposition()
                })
                observers.append(center.addObserver(
                    forName: NSWindow.didEndLiveResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reposition()
                })
                installedWindow = window
            }

            reposition()
            DispatchQueue.main.async { [weak self] in
                self?.reposition()
            }
        }

        func reposition() {
            guard let window = installedWindow else { return }
            guard let titleField = titleField(in: window),
                  let container = titlebarContainer(for: titleField)
            else { return }

            if hosting.superview !== container {
                container.addSubview(hosting)
            }

            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            let width = max(22, size.width)
            let height = max(22, size.height)
            let titleFrame = titleField.convert(titleField.bounds, to: container)
            hosting.frame = NSRect(
                x: titleFrame.maxX + 4,
                y: titleFrame.midY - (height / 2),
                width: width,
                height: height
            )
        }

        /// The title field's own parent is only as wide as the words, so a sibling button is clipped.
        private func titlebarContainer(for titleField: NSView) -> NSView? {
            var current: NSView? = titleField
            var match: NSView?
            while let view = current {
                let name = String(describing: type(of: view))
                if name.localizedCaseInsensitiveContains("titlebar") || name.contains("NSToolbarView") {
                    match = view
                }
                current = view.superview
            }
            return match ?? titleField.superview
        }

        private func titleField(in window: NSWindow) -> NSTextField? {
            let selector = NSSelectorFromString("_titleTextField")
            if window.responds(to: selector),
               let field = window.perform(selector)?.takeUnretainedValue() as? NSTextField {
                return field
            }

            guard let root = window.contentView?.superview else { return nil }
            var match: NSTextField?
            func walk(_ view: NSView) {
                if match == nil,
                   let field = view as? NSTextField,
                   !field.isEditable,
                   field.stringValue == window.title,
                   isInTitlebar(field) {
                    match = field
                    return
                }
                for subview in view.subviews where match == nil {
                    walk(subview)
                }
            }
            walk(root)
            return match
        }

        private func isInTitlebar(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let view = current {
                if String(describing: type(of: view)).localizedCaseInsensitiveContains("titlebar") {
                    return true
                }
                current = view.superview
            }
            return false
        }

        /// Earlier builds pinned the info button to the leading title-bar slot.
        private func removeLegacyAccessories(from window: NSWindow) {
            let accessories = window.titlebarAccessoryViewControllers
            for index in accessories.indices.reversed() {
                let controller = accessories[index]
                let marker = objc_getAssociatedObject(controller, &legacyMarkerKey) as? Bool == true
                let isLeadingInfo = controller.layoutAttribute == .leading
                    && controller.view is NSHostingView<AnyView>
                if marker || isLeadingInfo {
                    window.removeTitlebarAccessoryViewController(at: index)
                }
            }
        }
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.attach(from: self)
            }
        }

        override func layout() {
            super.layout()
            coordinator?.reposition()
        }
    }
}

private var legacyMarkerKey = "com.photoviewer.titlebarAccessory.marker"

private struct AppTitlebarInfoButton: View {
    @Bindable var appUpdate: AppUpdateModel

    var body: some View {
        AppInfoButton(appUpdate: appUpdate, style: .titlebar)
            .fixedSize()
    }
}

extension View {
    func installTitlebarInfoButton(appUpdate: AppUpdateModel) -> some View {
        background {
            TitlebarInfoButtonInstaller(appUpdate: appUpdate)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }
}
