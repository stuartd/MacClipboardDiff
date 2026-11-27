import AppKit

@MainActor
final class StatusMenu: NSMenu, NSMenuDelegate {
    private let controller: ClipDiffController
    private let modifierFlags: () -> NSEvent.ModifierFlags

    init(
        controller: ClipDiffController,
        modifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.controller = controller
        self.modifierFlags = modifierFlags
        super.init(title: "ClipDiff")
        delegate = self
        menuNeedsUpdate(self)
    }

    required init(coder: NSCoder) {
        fatalError("ClipDiff creates its status menu programmatically.")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let showDiagnosticLog = modifierFlags().contains(.option)
        let login = controller.loginItemManager
        login.refreshStatus()
        controller.refreshExternalDiffTools()

        // Keep the shortcut hint in the label. Carbon handles the global shortcut.
        let shortcutHint = controller.globalShortcut.displayString.map(String.init).joined(separator: "\u{2009}")
        let showDiff = ActionMenuItem(
            controller.isGlobalShortcutAvailable
                ? "Show Diff  \(shortcutHint)"
                : "Show Diff (shortcut unavailable)",
            symbol: "square.split.2x1"
        ) { [controller] in
            controller.showDiff()
        }
        showDiff.isEnabled = controller.canDiff

        let startAtLogin = ActionMenuItem(
            login.requiresApproval ? "Start at Login (approval required)" : "Start at Login"
        ) {
            login.setEnabled(!login.isRequested)
        }
        startAtLogin.state = login.isRequested ? .on : .off

        var items: [NSMenuItem] = [
            showDiff,
            ActionMenuItem("Change Keyboard Shortcut…", symbol: "keyboard") { [controller] in
                controller.showShortcutSettings()
            },
            ActionMenuItem("Finder Menu Settings…", symbol: "puzzlepiece.extension") { [controller] in
                controller.showFinderIntegrationSettings()
            },
            diffViewerItem(),
            startAtLogin
        ]
        if login.requiresApproval {
            items.append(ActionMenuItem("Open Login Items…") { login.openSystemSettings() })
        }
        if let message = controller.lastError {
            let error = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            error.attributedTitle = NSAttributedString(string: message, attributes: [.foregroundColor: NSColor.systemRed])
            error.isEnabled = false
            items.append(error)
        }

        items.append(.separator())
        if showDiagnosticLog {
            items.append(ActionMenuItem("Open Diagnostic Log…", symbol: "doc.text.magnifyingglass") { [controller] in
                controller.showDiagnosticLog()
            })
        }
        items.append(contentsOf: updateItems())
        items.append(ActionMenuItem("About ClipDiff", symbol: "info.circle") { [controller] in controller.showAbout() })
        items.append(ActionMenuItem("Quit ClipDiff", symbol: "xmark.circle", keyEquivalent: "q") { NSApp.terminate(nil) })
        menu.items = items
    }

    private func diffViewerItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Diff viewer: \(controller.diffViewerName)", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        let menu = NSMenu(title: "Diff viewer")
        menu.autoenablesItems = false
        let selectedID = controller.selectedExternalDiffTool?.id
        let builtIn = ActionMenuItem("Built-in viewer") { [controller] in controller.selectExternalDiffTool(nil) }
        builtIn.state = selectedID == nil ? .on : .off
        menu.addItem(builtIn)
        for choice in controller.externalDiffTools {
            let viewer = ActionMenuItem(choice.displayName) { [controller] in controller.selectExternalDiffTool(choice) }
            viewer.state = choice.id == selectedID ? .on : .off
            menu.addItem(viewer)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Choose Application…", symbol: "folder") { [controller] in
            controller.chooseExternalDiffTool()
        })

        if controller.shouldRecommendMacDiff {
            menu.addItem(.separator())
            let recommendation = ActionMenuItem("Get MacDiff…", symbol: "arrow.up.right.square") {
                NSWorkspace.shared.open(URL(string: "https://github.com/stuartd/macdiff/releases/latest")!)
            }
            recommendation.toolTip = "A native companion diff viewer for ClipDiff"
            menu.addItem(recommendation)
        }
        item.submenu = menu
        return item
    }

    private func updateItems() -> [NSMenuItem] {
        let checker = controller.updateChecker
        var items: [NSMenuItem] = []
        if let version = checker.availableVersion {
            items.append(ActionMenuItem("Upgrade Available…") {
                UpdateAlerts.showUpgrade(version, checker: checker)
            })
        }
        let check = ActionMenuItem(checker.isChecking ? "Checking for Updates…" : "Check for Updates…") {
            Task { UpdateAlerts.show(await checker.check(manual: true), checker: checker) }
        }
        check.isEnabled = !checker.isChecking
        items.append(check)

        let automatic = ActionMenuItem("Automatically Check for Updates") {
            let enable = checker.automaticPreference != true
            if !enable || UpdateAlerts.askForConsent() {
                checker.setAutomaticChecks(enable)
            }
        }
        automatic.isEnabled = checker.installedVersion != nil
        automatic.state = checker.automaticPreference == true ? .on : .off
        items.append(automatic)
        return items
    }
}

@MainActor
private final class ActionMenuItem: NSMenuItem, NSMenuItemValidation {
    private let perform: () -> Void

    init(_ title: String, symbol: String? = nil, keyEquivalent: String = "", perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        target = self
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        fatalError("ClipDiff creates its menu commands programmatically.")
    }

    @objc private func invoke() { perform() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isEnabled }
}
