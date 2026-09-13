import AppKit
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    private static let pairMenuTitle = "Compare two selected files with ClipDiff"
    private static let currentMenuTitle = "Compare with current ClipDiff capture"

    override init() {
        super.init()

        // Finder Sync only asks an extension for contextual menus inside its
        // managed directories. ClipDiff supplies no badges or observation work;
        // the root scope exists solely to make the comparison action available.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let urls = FIFinderSyncController.default().selectedItemURLs(),
              let operation = Self.operation(for: urls) else {
            return nil
        }

        let menu = NSMenu()
        let item = NSMenuItem(
            title: operation == .compareWithCurrent ? Self.currentMenuTitle : Self.pairMenuTitle,
            action: #selector(compareSelectedFiles(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func compareSelectedFiles(_ sender: NSMenuItem) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              let operation = Self.operation(for: urls) else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        guard let requestURL = Self.comparisonRequestURL(for: urls, operation: operation) else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.open(
            [requestURL],
            withApplicationAt: containingApplicationURL,
            configuration: configuration
        ) { _, error in
            if error != nil {
                NSSound.beep()
            }
        }
    }

    private var containingApplicationURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum Operation: String {
        case compareSelectedFiles = "compare-selected-files"
        case compareWithCurrent = "compare-with-current"
    }

    private static func operation(for urls: [URL]) -> Operation? {
        guard (1...2).contains(urls.count) else { return nil }

        guard urls.allSatisfy({ url in
            guard url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return false
            }
            return true
        }) else { return nil }
        return urls.count == 1 ? .compareWithCurrent : .compareSelectedFiles
    }

    private static func comparisonRequestURL(for urls: [URL], operation: Operation) -> URL? {
        guard urls.count == (operation == .compareWithCurrent ? 1 : 2) else { return nil }

        var components = URLComponents()
        components.scheme = "clipdiff"
        components.host = operation.rawValue
        components.queryItems = urls.map {
            URLQueryItem(name: "file", value: $0.absoluteString)
        }
        return components.url
    }
}
