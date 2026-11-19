import SwiftUI

@main
struct clipdiffApp: App {
    @NSApplicationDelegateAdaptor(ClipDiffApplicationDelegate.self)
    private var appDelegate

    var body: some Scene {
        // Keep SwiftUI's application and window commands. AppKit owns the status menu.
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
