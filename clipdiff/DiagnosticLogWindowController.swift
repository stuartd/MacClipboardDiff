import AppKit
import SwiftUI

@MainActor
final class DiagnosticLogWindowController {
    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClipDiff Diagnostic Log"
            window.contentView = NSHostingView(rootView: DiagnosticLogView())
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct DiagnosticLogView: View {
    @State private var refresh = 0
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent ClipDiff events")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { refresh += 1 }
                    .disabled(text == nil && !failed)
            }
            .padding(12)

            Divider()

            if let text, !text.isEmpty {
                ScrollView {
                    Text(verbatim: text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else if failed || text != nil {
                VStack(spacing: 8) {
                    if failed {
                        Text("Couldn’t read the ClipDiff log.")
                        Text("~/Library/Logs/ClipDiff/")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("No diagnostic events recorded yet.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Reading the diagnostic log…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 440, minHeight: 240)
        .task(id: refresh) {
            text = nil
            failed = false
            let result = try? await ClipDiffLog.file?.read()
            guard !Task.isCancelled else { return }
            text = result
            failed = result == nil
        }
    }
}
