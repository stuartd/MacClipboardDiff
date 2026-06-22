import SwiftUI

@main
struct clipdiffApp: App {
    @StateObject private var controller = ClipDiffController()

    var body: some Scene {
        MenuBarExtra("ClipDiff", systemImage: "doc.on.clipboard") {
            MenuContentView(controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}
