import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var controller: ClipDiffController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            Divider()

            clipboardPreview

            Divider()

            Button {
                controller.showDiff()
            } label: {
                Label("Show Diff", systemImage: "square.split.2x1")
            }
            .disabled(!controller.canDiff)
            .keyboardShortcut("d", modifiers: [.command, .option])

            Toggle(isOn: $controller.isMonitoring) {
                Label("Monitor Clipboard", systemImage: "dot.radiowaves.left.and.right")
            }

            Button {
                controller.clearCapturedText()
            } label: {
                Label("Clear Captured Text", systemImage: "trash")
            }
            .disabled(controller.entries.isEmpty)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit ClipDiff", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.canDiff ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(controller.canDiff ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.statusText)
                    .font(.headline)

                Text("Shortcut: Option-Command-D")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var clipboardPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            EntryPreviewView(title: "Current", entry: controller.currentEntry)
            EntryPreviewView(title: "Previous", entry: controller.previousEntry)

            if let lastError = controller.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EntryPreviewView: View {
    let title: String
    let entry: ClipboardEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let entry {
                Text(entry.preview)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(entry.lineCount) lines, \(entry.characterCount) characters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
