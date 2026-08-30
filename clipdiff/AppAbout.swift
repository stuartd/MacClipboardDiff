import AppKit

@MainActor
enum AppAbout {
    static func show() {
        let bundle = Bundle.main
        let marketingVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let buildNumber = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
        let commit = bundle.object(
            forInfoDictionaryKey: "ClipDiffGitCommit"
        ) as? String

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "ClipDiff",
            .applicationIcon: NSApplication.shared.applicationIconImage!,
            .version: marketingVersion,
            .applicationVersion: AppVersionFormatter.applicationVersion(
                buildNumber: buildNumber,
                commit: commit
            ),
            .credits: credits
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static var credits: NSAttributedString {
        let result = NSMutableAttributedString(string: "A tiny local clipboard comparison tool.\n\n")
        result.append(NSAttributedString(string: "Created by Stuart Dunkeld\n"))
        result.append(link("stuartd.dev", destination: "https://stuartd.dev/"))
        result.append(NSAttributedString(string: "\n"))
        result.append(link(
            "MacClipboardDiff project",
            destination: "https://github.com/stuartd/MacClipboardDiff"
        ))
        return result
    }

    private static func link(_ title: String, destination: String) -> NSAttributedString {
        guard let url = URL(string: destination) else {
            return NSAttributedString(string: title)
        }
        return NSAttributedString(
            string: title,
            attributes: [
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
    }
}
