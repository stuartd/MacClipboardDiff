import AppKit
import SwiftUI

@MainActor
final class DiffWindowController {
    private weak var controller: ClipDiffController?
    private var window: NSWindow?

    init(controller: ClipDiffController) {
        self.controller = controller
    }

    func show() {
        guard let controller else { return }

        if window == nil {
            let contentView = DiffWindowView(controller: controller)
            let hostingView = NSHostingView(rootView: contentView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClipDiff"
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("ClipDiffWindow")
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
