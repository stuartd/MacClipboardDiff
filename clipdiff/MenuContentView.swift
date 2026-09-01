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

            if controller.isGlobalShortcutAvailable {
                showDiffButton(title: "Show Diff")
                    .keyboardShortcut("d", modifiers: [.command, .option])
            } else {
                showDiffButton(title: "Show Diff (shortcut unavailable)")
            }

            diffViewerMenu

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
                controller.showAbout()
            } label: {
                Label("About ClipDiff", systemImage: "info.circle")
            }

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

            Text(controller.statusText)
                .font(.headline)
        }
    }

    private var clipboardPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            EntryPreviewView(
                title: "Current",
                entry: controller.currentEntry,
                fileLabel: controller.fileLabels.current
            )
            EntryPreviewView(
                title: "Previous",
                entry: controller.previousEntry,
                fileLabel: controller.fileLabels.previous
            )

            if let lastError = controller.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func showDiffButton(title: String) -> some View {
        Button {
            controller.showDiff()
        } label: {
            Label(title, systemImage: "square.split.2x1")
        }
        .disabled(!controller.canDiff)
    }

    private var diffViewerMenu: some View {
        Menu {
            Button {
                controller.selectExternalDiffTool(nil)
            } label: {
                viewerChoiceLabel(
                    "Built-in viewer",
                    isSelected: controller.selectedExternalDiffTool == nil
                )
            }

            if !controller.externalDiffTools.isEmpty {
                Divider()

                ForEach(controller.externalDiffTools) { choice in
                    Button {
                        controller.selectExternalDiffTool(choice)
                    } label: {
                        viewerChoiceLabel(
                            choice.displayName,
                            isSelected: controller.selectedExternalDiffTool?.id == choice.id
                        )
                    }
                }
            }

            Divider()

            Button {
                controller.chooseExternalDiffTool()
            } label: {
                Label("Choose Application…", systemImage: "folder")
            }
        } label: {
            Label("Diff viewer: \(controller.diffViewerName)", systemImage: "macwindow")
        }
    }

    @ViewBuilder
    private func viewerChoiceLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct EntryPreviewView: View {
    let title: String
    let entry: ClipboardEntry?
    let fileLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let entry {
                Text(entry.displayPreview(fileLabel: fileLabel))
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
