import SwiftUI

@main
struct clipdiffApp: App {
    @NSApplicationDelegateAdaptor(ClipDiffApplicationDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra("ClipDiff", systemImage: "doc.on.clipboard",
                     isInserted: .constant(appDelegate.controller != nil)) {
            if let controller = appDelegate.controller {
                MenuContentView(controller: controller)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
