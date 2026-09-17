import AppKit
import DeviceWorkspaceFeature
import SwiftUI

/// Makes the hosting window the compact window while `layout` is set.
///
/// The window is sized around the device, keeps the device's shape while the user resizes it from
/// any edge, refits when the device rotates, and gets its previous frame back afterwards.
///
/// Outside compact mode it also widens a window that starts smaller than `normalMinimumSize` (a frame
/// saved while compact, or while the inspector was hidden): the split view can't fit and AppKit throws.
struct CompactWindowController: NSViewRepresentable {
    let layout: CompactWindowLayout?
    let normalMinimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let layout = layout
        let minimum = normalMinimumSize
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.normalMinimumSize = minimum
            context.coordinator.apply(layout, to: window)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Stands in as the window delegate while compact, forwarding everything it doesn't handle to
    /// SwiftUI's own delegate.
    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private var layout: CompactWindowLayout?
        private weak var window: NSWindow?
        private nonisolated(unsafe) weak var originalDelegate: (any NSWindowDelegate)?
        private var savedFrame: NSRect?
        private var savedMinSize: NSSize?
        private var terminationObserver: (any NSObjectProtocol)?
        var normalMinimumSize = CGSize.zero

        func apply(_ newLayout: CompactWindowLayout?, to window: NSWindow) {
            let previous = layout
            layout = newLayout
            switch (previous, newLayout) {
            case (nil, let layout?):
                enter(layout, window: window)
            case (let previous?, let layout?) where previous != layout:
                let content = layout.rotated(
                    from: previous, content: contentSize(of: window), within: bounds(of: window))
                setContentSize(content, of: window, animate: true)
            case (_?, nil):
                exit(window)
            case (nil, nil):
                growToNormalMinimum(window)
            case (_?, _?):
                break
            }
        }

        func detach() {
            guard let window, layout != nil else { return }
            layout = nil
            exit(window)
        }

        // MARK: - Entering and leaving

        private func enter(_ layout: CompactWindowLayout, window: NSWindow) {
            self.window = window
            savedFrame = window.frame
            savedMinSize = window.minSize
            // The next launch starts in the normal layout, so quitting must not save the compact frame.
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, let frame = self.savedFrame else { return }
                    window.setFrame(frame, display: false)
                    window.saveFrame(usingName: window.frameAutosaveName)
                }
            }
            if window.delegate !== self {
                originalDelegate = window.delegate
                window.delegate = self
            }
            let height = layout.clampedDeviceHeight(
                layout.deviceHeight(in: contentSize(of: window)), within: bounds(of: window))
            setContentSize(layout.contentSize(deviceHeight: height), of: window, animate: true)
            // The toolbar can change height once SwiftUI swaps in the compact layout.
            DispatchQueue.main.async { [weak self] in
                guard let self, let layout = self.layout, let window = self.window else { return }
                let height = layout.deviceHeight(in: self.contentSize(of: window))
                self.setContentSize(layout.contentSize(deviceHeight: height), of: window, animate: false)
            }
        }

        private func exit(_ window: NSWindow) {
            if let terminationObserver {
                NotificationCenter.default.removeObserver(terminationObserver)
            }
            terminationObserver = nil
            if window.delegate === self {
                window.delegate = originalDelegate
            }
            originalDelegate = nil
            if let savedMinSize {
                window.minSize = savedMinSize
            }
            if let savedFrame {
                window.setFrame(savedFrame, display: true, animate: true)
            }
            savedFrame = nil
            savedMinSize = nil
            self.window = nil
        }

        /// Widens or heightens the normal window in place when it's below its minimum size.
        private func growToNormalMinimum(_ window: NSWindow) {
            let content = contentSize(of: window)
            guard content.width < normalMinimumSize.width || content.height < normalMinimumSize.height else { return }
            let chrome = chrome(of: window)
            var frame = window.frame
            let size = NSSize(
                width: max(content.width, normalMinimumSize.width) + chrome.width,
                height: max(content.height, normalMinimumSize.height) + chrome.height
            )
            frame.origin.y += frame.height - size.height
            frame.size = size
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                frame.origin.y = max(frame.origin.y, visible.minY)
            }
            window.setFrame(frame, display: true)
        }

        // MARK: - Resizing

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            let proposed = originalDelegate?.windowWillResize?(sender, to: frameSize) ?? frameSize
            guard let layout else { return proposed }
            let chrome = chrome(of: sender)
            let content = layout.resized(
                from: contentSize(of: sender),
                to: NSSize(width: proposed.width - chrome.width, height: proposed.height - chrome.height),
                within: bounds(of: sender)
            )
            return NSSize(width: content.width + chrome.width, height: content.height + chrome.height)
        }

        /// Sizes the window for `content`, keeping its top edge and horizontal center on screen.
        private func setContentSize(_ content: CGSize, of window: NSWindow, animate: Bool) {
            guard let layout else { return }
            let chrome = chrome(of: window)
            let minimum = layout.minimumContentSize
            window.minSize = NSSize(width: minimum.width + chrome.width, height: minimum.height + chrome.height)
            var frame = window.frame
            let size = NSSize(width: content.width + chrome.width, height: content.height + chrome.height)
            frame.origin.x += (frame.width - size.width) / 2
            frame.origin.y += frame.height - size.height
            frame.size = size
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            }
            guard frame != window.frame else { return }
            window.setFrame(frame, display: true, animate: animate)
        }

        /// Title bar and toolbar, which sit outside the content area.
        private func chrome(of window: NSWindow) -> NSSize {
            NSSize(
                width: window.frame.width - window.contentLayoutRect.width,
                height: window.frame.height - window.contentLayoutRect.height
            )
        }

        private func contentSize(of window: NSWindow) -> CGSize {
            window.contentLayoutRect.size
        }

        /// The largest content area the screen allows.
        private func bounds(of window: NSWindow) -> CGSize {
            let visible = window.screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            let chrome = chrome(of: window)
            return CGSize(width: visible.width - chrome.width, height: visible.height - chrome.height)
        }

        // MARK: - Forwarding to SwiftUI's delegate

        override nonisolated func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
        }

        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            if let originalDelegate, originalDelegate.responds(to: selector) {
                return originalDelegate
            }
            return super.forwardingTarget(for: selector)
        }
    }
}
