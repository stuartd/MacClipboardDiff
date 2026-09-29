import AppKit

@MainActor
final class ClipDiffApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller: ClipDiffController?
    private let instanceLock: SingleInstanceLock?
    private let existingApplication: NSRunningApplication?
    private let startupError: Error?
    private var pendingOpenRequests: [[URL]] = []

    override init() {
        do {
            let lock = try SingleInstanceLock()
            instanceLock = lock
            startupError = nil
            // An older build may already be running without the lock. Preserve
            // its in-memory captures and hand off to it during this upgrade.
            existingApplication = lock.isOwner ? Bundle.main.bundleIdentifier.flatMap { identifier in
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                    .filter {
                        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                            && $0.isFinishedLaunching && !$0.isTerminated
                    }
                    .min { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }
            } : nil
            // A duplicate must never poll the clipboard or register a shortcut.
            controller = lock.isOwner && existingApplication == nil ? ClipDiffController() : nil
        } catch {
            instanceLock = nil
            existingApplication = nil
            startupError = error
            controller = nil
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let controller {
            controller.startGlobalShortcut()
        } else if let startupError {
            reportStartupFailure(startupError)
        } else {
            Task { await handOffToRunningInstance() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            pendingOpenRequests.append(urls)
            return
        }
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

    private func handOffToRunningInstance() async {
        // The lock owner may still be starting, including publishing its PID.
        for _ in 0..<40 {
            let owner = instanceLock?.ownerProcessIdentifier.flatMap {
                NSRunningApplication(processIdentifier: $0)
            }
            if let running = existingApplication ?? owner,
               running.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               running.bundleIdentifier == Bundle.main.bundleIdentifier,
               running.isFinishedLaunching,
               !running.isTerminated {
                do {
                    while !pendingOpenRequests.isEmpty {
                        let urls = pendingOpenRequests.removeFirst()
                        guard let appURL = running.bundleURL else { break }
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.createsNewApplicationInstance = false
                        configuration.addsToRecentItems = false
                        try await NSWorkspace.shared.open(
                            urls, withApplicationAt: appURL, configuration: configuration
                        )
                    }
                    // Activation alone never invokes Show Diff or creates a window.
                    if #available(macOS 14.0, *) {
                        running.activate(from: .current, options: [])
                    } else {
                        running.activate(options: [.activateIgnoringOtherApps])
                    }
                    NSApp.terminate(nil)
                } catch {
                    reportStartupFailure(error)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Do not start a second controller if the owner cannot be activated.
        NSApp.terminate(nil)
    }

    private func reportStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ClipDiff couldn’t finish launching."
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}
