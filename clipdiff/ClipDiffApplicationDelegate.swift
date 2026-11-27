import AppKit
import Combine

@MainActor
final class ClipDiffApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller: ClipDiffController?
    private let instanceLock: SingleInstanceLock?
    private let existingApplication: NSRunningApplication?
    private let startupError: Error?
    private var pendingOpenRequests: [[URL]] = []
    private var suppressUpdateConsentPrompt = false
    private var statusItem: NSStatusItem?
    private var upgradePromptObservation: AnyCancellable?

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
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipDiff")
            statusItem.button?.toolTip = "ClipDiff"
            statusItem.menu = StatusMenu(controller: controller)
            self.statusItem = statusItem
            ClipDiffLog.app.notice("ClipDiff started")
            // The initial Apple event is available during this callback, before
            // the run-loop callback below. Skip setup questions on login/service launches.
            if LoginItemLaunchContext.isAutomaticLaunch(NSAppleEventManager.shared().currentAppleEvent) {
                controller.loginItemManager.suppressAutomaticPrompt()
                suppressUpdateConsentPrompt = true
            }
            controller.startGlobalShortcut()
            controller.updateChecker.start()
            // Wait for initial file-open events and let the launch finish. Use a
            // run-loop callback so an alert doesn't block main-queue work.
            perform(#selector(promptToStartAtLogin), with: nil, afterDelay: 0)
        } else if let startupError {
            reportStartupFailure(startupError)
        } else {
            Task { await handOffToRunningInstance() }
        }
    }

    @objc private func promptToStartAtLogin() {
        if NSApp.modalWindow == nil {
            controller?.loginItemManager.promptIfNeeded()
        }
        perform(#selector(promptForAutomaticUpdates), with: nil, afterDelay: 0)
    }

    @objc private func promptForAutomaticUpdates() {
        guard let checker = controller?.updateChecker else { return }
        if !suppressUpdateConsentPrompt, NSApp.modalWindow == nil,
           checker.installedVersion != nil, checker.automaticPreference == nil {
            checker.setAutomaticChecks(UpdateAlerts.askForConsent())
        }

        upgradePromptObservation = checker.$availableVersion.combineLatest(checker.$isChecking)
            .sink { [weak self] _ in
                // Use the default run-loop mode so the prompt waits for menu tracking
                // and other modal alerts to finish. Published values emit before storage updates.
                self?.perform(#selector(ClipDiffApplicationDelegate.promptForUpgrade), with: nil, afterDelay: 0)
            }
    }

    @objc private func promptForUpgrade() {
        guard NSApp.modalWindow == nil, let checker = controller?.updateChecker,
              let version = checker.upgradeToOffer else { return }
        UpdateAlerts.showUpgrade(version, checker: checker)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let controller {
            controller.updateChecker.stop()
            ClipDiffLog.app.notice("ClipDiff stopped")
        }
        ClipDiffLog.file?.flush()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            pendingOpenRequests.append(urls)
            return
        }
        controller.loginItemManager.suppressAutomaticPrompt()
        suppressUpdateConsentPrompt = true
        if urls.count == 1, urls[0].scheme?.lowercased() == FinderComparisonRequest.scheme {
            guard let request = FinderComparisonRequest(url: urls[0]) else {
                ClipDiffLog.app.error("Received an invalid Finder comparison request")
                return
            }
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
        ClipDiffLog.app.error("Timed out waiting for the running ClipDiff instance")
        NSApp.terminate(nil)
    }

    private func reportStartupFailure(_ error: Error) {
        ClipDiffLog.app.error("ClipDiff startup failed with code \((error as NSError).code)")
        let alert = NSAlert()
        alert.messageText = "ClipDiff couldn’t finish launching."
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}
