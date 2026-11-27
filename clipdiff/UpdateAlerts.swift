import AppKit

@MainActor
enum UpdateAlerts {
    static func askForConsent() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Check for ClipDiff updates automatically?"
        alert.informativeText = """
        If set, ClipDiff will check github.com/stuartd/MacClipboardDiff daily to check for a new release. 

        If not set, you can check for updates manually from the ClipDiff menu.
        """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showUpgrade(_ version: ReleaseVersion, checker: UpdateChecker) {
        checker.markUpgradeOffered(version)

        let alert = NSAlert()
        alert.messageText = "A ClipDiff upgrade is available."
        alert.informativeText = "Open the download page? Choose Later to be reminded the next time you open ClipDiff."
        alert.addButton(withTitle: "Later").keyEquivalent = "\r"
        alert.addButton(withTitle: "No")
        alert.addButton(withTitle: "Yes")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertThirdButtonReturn:
            let releasePage = GitHubReleaseClient.releasePage(for: version)
            if !NSWorkspace.shared.open(releasePage) {
                ClipDiffLog.updates.error("Could not open the GitHub release page")
                let errorAlert = NSAlert()
                errorAlert.messageText = "Couldn’t open the release page."
                errorAlert.informativeText = "Visit the ClipDiff GitHub releases page to download the upgrade."
                errorAlert.runModal()
            }
        case .alertSecondButtonReturn:
            checker.skipUpgrade(version)
        default:
            checker.deferUpgrade(version)
        }
    }

    static func show(_ outcome: UpdateChecker.Outcome, checker: UpdateChecker) {
        let alert = NSAlert()
        switch outcome {
        case .available(let version):
            showUpgrade(version, checker: checker)
            return
        case .current:
            alert.messageText = "ClipDiff is up to date."
        case .unversionedBuild:
            alert.messageText = "This build has no release version."
            alert.informativeText = "Update checks compare the version of a tagged ClipDiff build with the latest GitHub release."
        case .failed:
            alert.messageText = "Couldn’t check for updates."
            alert.informativeText = "Try again later. The ClipDiff diagnostic log has more details."
            alert.alertStyle = .warning
        case .skipped:
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
