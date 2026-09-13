import AppKit

@MainActor
final class ClipDiffApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = ClipDiffController()

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.count == 1, urls[0].scheme?.lowercased() == FinderComparisonRequest.scheme {
            guard let request = FinderComparisonRequest(url: urls[0]) else { return }
            switch request.operation {
            case .compareSelectedFiles:
                controller.compareSelectedFiles(request.fileURLs)
            case .compareWithCurrent:
                controller.compareWithCurrentCapture(request.fileURLs[0])
            }
            return
        }

        if urls.count == 2, urls.allSatisfy(\.isFileURL) {
            controller.compareSelectedFiles(urls)
        }
    }
}
