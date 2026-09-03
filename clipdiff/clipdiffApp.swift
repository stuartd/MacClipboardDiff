import SwiftUI

@main
struct clipdiffApp: App {
    @NSApplicationDelegateAdaptor(ClipDiffApplicationDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra("ClipDiff", systemImage: "doc.on.clipboard") {
            MenuContentView(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.menu)
    }
}
