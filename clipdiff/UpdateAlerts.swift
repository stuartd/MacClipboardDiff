import AppKit
import OSLog

@MainActor
enum UpdateAlerts {
    static func askForConsent() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Check for ClipDiff updates automatically?"
        alert.informativeText = """
        ClipDiff can contact api.github.com up to once a day to look for new releases. GitHub receives your IP address and normal request metadata. Update checks send no clipboard contents or file information.

        You can change this in the ClipDiff menu. To install an update, download it from GitHub yourself.
        """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func show(_ outcome: UpdateChecker.Outcome) {
        let alert = NSAlert()
        switch outcome {
        case .available(let version):
            alert.messageText = "ClipDiff \(version.displayName) is available."
            alert.informativeText = "Open the GitHub release page to download ClipDiff-macOS.zip."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Close").keyEquivalent = "\u{1b}"
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if !NSWorkspace.shared.open(GitHubReleaseClient.releasePage(for: version)) {
                ClipDiffLog.updates.error("Could not open the GitHub release page")
                let errorAlert = NSAlert()
                errorAlert.messageText = "Couldn’t open the release page."
                errorAlert.informativeText = GitHubReleaseClient.releasePage(for: version).absoluteString
                errorAlert.runModal()
            }
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
