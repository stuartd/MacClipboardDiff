import AppKit

@MainActor
final class ClipDiffApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = ClipDiffController()

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.count == 1,
           let request = FinderComparisonRequest(url: urls[0]) {
            controller.compareSelectedFiles(request.fileURLs)
            return
        }

        controller.compareSelectedFiles(urls)
    }
}
