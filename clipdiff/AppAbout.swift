import AppKit
import SwiftUI

@MainActor
enum AppAbout {
    private static var panel: NSPanel?

    static func show() {
        if panel == nil {
            let aboutPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 364, height: 338),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutPanel.title = "About ClipDiff"
            aboutPanel.isReleasedWhenClosed = false
            aboutPanel.contentView = NSHostingView(rootView: ClipDiffAboutView())
            aboutPanel.center()
            panel = aboutPanel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct ClipDiffAboutView: View {
    private let bundle = Bundle.main

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("ClipDiff")
                    .font(.system(size: 26, weight: .semibold))
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Developer").foregroundStyle(.secondary)
                    Text("Stuart Dunkeld")
                }
                GridRow {
                    Text("Company").foregroundStyle(.secondary)
                    Text("Rose Hill Solutions")
                }
                GridRow {
                    Text("Commit").foregroundStyle(.secondary)
                    Text(AppVersionFormatter.shortCommit(
                        bundle.object(forInfoDictionaryKey: "ClipDiffGitCommit") as? String
                    ) ?? "Unavailable")
                }
                .padding(.top, 8)
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    Link("stuartd/MacClipboardDiff", destination: URL(string: "https://github.com/stuartd/MacClipboardDiff")!)
                }
            }
            .font(.system(size: 14))
            .textSelection(.enabled)

            Text("© 2026 Stuart Dunkeld")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 364, height: 338)
    }
}
