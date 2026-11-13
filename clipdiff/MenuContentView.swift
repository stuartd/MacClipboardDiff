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
                    ? "Show Diff  \(shortcutHint)"
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
                    "Finder Menu Settings…",
                    systemImage: "puzzlepiece.extension"
                )
            }

            diffViewerMenu

            StartAtLoginMenuContent(manager: controller.loginItemManager)

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

    private var shortcutHint: String {
        controller.globalShortcut.displayString.map(String.init).joined(separator: "\u{2009}")
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
            // Use native menu selection state so the tick appears in the menu margin.
            Picker("Diff viewer", selection: diffViewerSelection) {
                Text("Built-in viewer")
                    .tag(nil as String?)

                ForEach(controller.externalDiffTools) { choice in
                    Text(choice.displayName)
                        .tag(choice.id as String?)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button {
                controller.chooseExternalDiffTool()
            } label: {
                Label("Choose Application…", systemImage: "folder")
            }

            if controller.shouldRecommendMacDiff {
                Divider()

                Link(destination: URL(string: "https://github.com/stuartd/macdiff/releases/latest")!) {
                    Label("Get MacDiff…", systemImage: "arrow.up.right.square")
                }
                .help("A native companion diff viewer for ClipDiff")
            }
        } label: {
            Label("Diff viewer: \(controller.diffViewerName)", systemImage: "macwindow")
        }
    }

    private var diffViewerSelection: Binding<String?> {
        Binding(
            get: { controller.selectedExternalDiffTool?.id },
            set: { selectedID in
                let choice = controller.externalDiffTools.first { $0.id == selectedID }
                controller.selectExternalDiffTool(choice)
            }
        )
    }
}

private struct StartAtLoginMenuContent: View {
    @ObservedObject var manager: LoginItemManager

    var body: some View {
        Toggle(
            manager.requiresApproval ? "Start at Login (approval required)" : "Start at Login",
            isOn: Binding(
                get: { manager.isRequested },
                set: { manager.setEnabled($0) }
            )
        )
        if manager.requiresApproval {
            Button("Open Login Items…") {
                manager.openSystemSettings()
            }
        }
    }
}
