import AppKit
import SwiftUI

/// Fires when the pointer moves or scrolls in the current window (fullscreen photo chrome auto-hide).
struct PointerActivityTracker: NSViewRepresentable {
    var onActivity: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onActivity = onActivity
    }

    final class TrackerView: NSView {
        var onActivity: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitorIfNeeded()
        }

        override func removeFromSuperview() {
            removeMonitor()
            super.removeFromSuperview()
        }

        private func installMonitorIfNeeded() {
            guard window != nil, monitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .scrollWheel,
            ]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                self.onActivity?()
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}