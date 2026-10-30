import AppKit
import SwiftUI

@MainActor
enum AppAbout {
    private static var panel: NSPanel?

    static func show() {
        if panel == nil {
            let contentView = NSHostingView(rootView: ClipDiffAboutView())
            let aboutPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutPanel.title = "About ClipDiff"
            aboutPanel.isReleasedWhenClosed = false
            aboutPanel.contentView = contentView
            aboutPanel.center()
            panel = aboutPanel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func close() {
        panel?.close()
    }
}

private struct ClipDiffAboutView: View {
    private let bundle = Bundle.main

    private var version: AppVersionFormatter.AboutVersion {
        AppVersionFormatter.aboutVersion(
            releaseTag: bundle.object(forInfoDictionaryKey: "ClipDiffReleaseTag") as? String,
            commit: bundle.object(forInfoDictionaryKey: "ClipDiffGitCommit") as? String
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("ClipDiff")
                    .font(.system(size: 26, weight: .semibold))
            }

            VStack(spacing: 4) {
                Text("© Stuart Dunkeld 2026")
                Text("Rose Hill Solutions")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text(version.label).foregroundStyle(.secondary)
                    Text(version.value)
                }
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    Link("stuartd/MacClipboardDiff", destination: URL(string: "https://github.com/stuartd/MacClipboardDiff")!)
                }
            }
            .font(.system(size: 14))
            .textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 380)
        .onExitCommand(perform: AppAbout.close)
    }
}
