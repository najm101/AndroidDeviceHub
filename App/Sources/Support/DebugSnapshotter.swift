#if DEBUG
    import AppKit

    /// Debug builds only: saves PNGs of the app's own windows on request, so UI changes can be checked
    /// from scripts without Screen Recording permission.
    ///
    ///     Scripts/snapshot.sh /tmp/shots            # writes one PNG per visible window
    ///     Scripts/snapshot.sh /tmp/shots 1300x900   # resizes the main window first
    @MainActor
    enum DebugSnapshotter {
        static let notification = Notification.Name("io.github.najm101.AndroidDeviceApp.debugSnapshot")

        static func install() {
            DistributedNotificationCenter.default().addObserver(
                forName: notification, object: nil, queue: .main
            ) { note in
                guard let request = note.object as? String else { return }
                // "<directory>|<width>x<height>", the size being optional.
                let parts = request.split(separator: "|", maxSplits: 1).map(String.init)
                let size = parts.count > 1 ? parseSize(parts[1]) : nil
                MainActor.assumeIsolated {
                    if let size, let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) {
                        window.setFrame(onScreenFrame(for: window, size: size), display: true)
                        window.layoutIfNeeded()
                    }
                    capture(into: URL(filePath: parts[0], directoryHint: .isDirectory))
                }
            }
        }

        /// Keeps the top-left corner where possible, but the whole window on its screen, so scripts and
        /// UI tests never click through to another display.
        private static func onScreenFrame(for window: NSWindow, size: NSSize) -> NSRect {
            var frame = NSRect(
                x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height)
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
                frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            }
            return frame
        }

        private nonisolated static func parseSize(_ text: String) -> NSSize? {
            let values = text.split(separator: "x").compactMap { Double($0) }
            return values.count == 2 ? NSSize(width: values[0], height: values[1]) : nil
        }

        private static func capture(into directory: URL) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                // The frame view includes the title bar and toolbar, not just the content.
                guard let view = window.contentView?.superview ?? window.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.isEmpty ? "window-\(index)" : window.title
                let file = directory.appending(path: "\(name.replacingOccurrences(of: "/", with: "-")).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
    }
#endif
