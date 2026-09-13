import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var controller: ClipDiffController

    var body: some View {
        Group {
            // AppKit dims its native shortcut column even for enabled commands.
            // Keep the hint in the label so both share the same enabled styling;
            // HotKeyController handles the global shortcut independently.
            showDiffButton(
                title: controller.isGlobalShortcutAvailable
                    ? "Show Diff  \(controller.globalShortcut.displayString)"
                    : "Show Diff (shortcut unavailable)"
            )

            Button {
                controller.showShortcutSettings()
            } label: {
                Label(
                    "Change Keyboard Shortcut…",
                    systemImage: "keyboard"
                )
            }

            Button {
                controller.showFinderIntegrationSettings()
            } label: {
                Label(
                    controller.isFinderIntegrationEnabled
                        ? "Finder menu: Enabled…"
                        : "Enable Finder menu…",
                    systemImage: controller.isFinderIntegrationEnabled
                        ? "checkmark.circle"
                        : "puzzlepiece.extension"
                )
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

            if let lastError = controller.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
