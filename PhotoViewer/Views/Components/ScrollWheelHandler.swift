import AppKit
import SwiftUI

/// Delivers vertical scroll-wheel deltas when the pointer is over the host view.
struct ScrollWheelHandler: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> HandlerView {
        let view = HandlerView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: HandlerView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class HandlerView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

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
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }
                let dy = event.scrollingDeltaY
                guard abs(dy) > 0.01 else { return event }
                self.onScroll?(dy)
                return nil
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