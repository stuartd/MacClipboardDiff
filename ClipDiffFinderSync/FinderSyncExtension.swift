import AppKit
import FinderSync
import UniformTypeIdentifiers

final class FinderSyncExtension: FIFinderSync {
    private static let pairMenuTitle = "Compare two selected files with ClipDiff"
    private static let currentMenuTitle = "Compare with current ClipDiff capture"
    private var captureIdentity: FinderCaptureIdentity?
    private weak var comparisonMenu: NSMenu?

    override init() {
        super.init()

        // Finder Sync only asks an extension for contextual menus inside its
        // managed directories. ClipDiff supplies no badges or observation work;
        // the root scope exists solely to make the comparison action available.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(captureIdentityChanged(_:)),
            name: FinderCaptureIdentity.changedNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        requestCaptureIdentity()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Refresh the cache without blocking Finder, including after an app restart.
        requestCaptureIdentity()
        guard menuKind == .contextualMenuForItems,
              let urls = FIFinderSyncController.default().selectedItemURLs(),
              let operation = operation(for: urls) else {
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
        comparisonMenu = menu
        return menu
    }

    @objc private func compareSelectedFiles(_ sender: NSMenuItem) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              let operation = operation(for: urls) else {
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

    @objc private func captureIdentityChanged(_ notification: Notification) {
        guard let identity = FinderCaptureIdentity(notificationObject: notification.object),
              let application = NSRunningApplication(processIdentifier: identity.processIdentifier),
              application.bundleIdentifier == "stuartd.clipdiff",
              !application.isTerminated else { return }
        if let current = captureIdentity,
           current.processIdentifier == identity.processIdentifier,
           current.sessionID == identity.sessionID,
           current.revision >= identity.revision { return }
        captureIdentity = identity
        // The extension can start on the first right-click. Apply the initial
        // reply to that open menu too, rather than waiting for a second click.
        if let urls = FIFinderSyncController.default().selectedItemURLs(),
           urls.count == 1,
           identity.matches(urls[0], pasteboardChangeCount: NSPasteboard.general.changeCount) {
            comparisonMenu?.removeAllItems()
        }
    }

    private func requestCaptureIdentity() {
        DistributedNotificationCenter.default().postNotificationName(
            FinderCaptureIdentity.requestNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func operation(for urls: [URL]) -> Operation? {
        guard (1...2).contains(urls.count) else { return nil }

        if urls.count == 1, let identity = captureIdentity {
            if let application = NSRunningApplication(processIdentifier: identity.processIdentifier),
               application.bundleIdentifier == "stuartd.clipdiff",
               !application.isTerminated {
                // A fresh pathname copy may still be waiting for the app's
                // bounded reader. An older capture must not hide this command.
                guard !identity.matches(
                    urls[0], pasteboardChangeCount: NSPasteboard.general.changeCount
                ) else { return nil }
            } else {
                captureIdentity = nil
            }
        }

        guard urls.allSatisfy({ url in
            guard url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  values.isRegularFile == true else {
                return false
            }
            guard let type = values.contentType else { return true }
            // Unknown extensions can still contain source code or plain text.
            // Reject known binary formats without reading files in Finder's menu callback.
            let binaryTypes: [UTType] = [
                .image, .audiovisualContent, .archive, .pdf,
                .executable, .font, .database
            ]
            return !binaryTypes.contains { type.conforms(to: $0) }
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
