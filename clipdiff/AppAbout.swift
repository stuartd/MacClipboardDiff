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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle
        ]

        let result = NSMutableAttributedString(
            string: "A minimal clipboard diff tool.\n\n",
            attributes: attributes
        )
        result.append(link(
            "MacClipboardDiff project",
            destination: "https://github.com/stuartd/MacClipboardDiff",
            attributes: attributes
        ))
        return result
    }

    private static func link(
        _ title: String,
        destination: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard let url = URL(string: destination) else {
            return NSAttributedString(string: title, attributes: attributes)
        }

        var linkAttributes = attributes
        linkAttributes[.link] = url
        linkAttributes[.foregroundColor] = NSColor.linkColor
        linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue

        return NSAttributedString(
            string: title,
            attributes: linkAttributes
        )
    }
}
