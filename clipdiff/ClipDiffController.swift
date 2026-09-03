import AppKit
import Combine
import FinderSync
import Foundation

@MainActor
final class ClipDiffController: ObservableObject {
    @Published private(set) var activeDiff: DiffDocument?
    @Published private(set) var lastError: String?
    @Published private(set) var isGlobalShortcutAvailable = true
    @Published private(set) var globalShortcut: GlobalShortcut
    @Published private(set) var externalDiffTools: [ExternalDiffToolChoice]
    @Published var viewMode: DiffViewMode = .sideBySide

    private let clipboard: ClipboardStore
    private let fileReader: CopiedFileTextReader
    private let history: ClipboardHistory
    private let globalShortcutSettingsStore: GlobalShortcutSettingsStore
    private let externalDiffSettingsStore: ExternalDiffSettingsStore
    private let externalDiffLauncher: ExternalDiffLauncher
    private var externalDiffSettings: ExternalDiffSettings
    private var lastRequestedChangeCount: Int
    private var pendingFileReadChangeCount: Int?
    private var pendingFileRead: Task<Void, Never>?
    private var pendingSelectedFileRead: Task<Void, Never>?
    private var timer: Timer?
    private var diffWindowController: DiffWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var hotKeyController: HotKeyController?
    private var applicationWillTerminateObserver: NSObjectProtocol?

    convenience init() {
        self.init(clipboard: SystemClipboardStore())
    }

    init(
        clipboard: ClipboardStore,
        fileReader: CopiedFileTextReader = CopiedFileTextReader()
    ) {
        self.clipboard = clipboard
        self.fileReader = fileReader
        globalShortcutSettingsStore = GlobalShortcutSettingsStore()
        globalShortcut = globalShortcutSettingsStore.load()
        externalDiffSettingsStore = ExternalDiffSettingsStore()
        externalDiffSettings = externalDiffSettingsStore.load()
        externalDiffLauncher = ExternalDiffLauncher()
        externalDiffTools = ExternalDiffToolDiscovery.findInstalled(
            selectedExecutablePath: externalDiffSettings.selectedExecutablePath
        )
        history = ClipboardHistory(startupChangeCount: clipboard.changeCount)
        lastRequestedChangeCount = clipboard.changeCount

        startMonitoring()

        let hotKeyController = HotKeyController(shortcut: globalShortcut) { [weak self] in
            Task { @MainActor in
                self?.showDiff()
            }
        }
        self.hotKeyController = hotKeyController
        isGlobalShortcutAvailable = hotKeyController.isRegistered

        applicationWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak externalDiffLauncher = externalDiffLauncher] _ in
            externalDiffLauncher?.cleanupAll()
        }

    }

    deinit {
        timer?.invalidate()
        pendingFileRead?.cancel()
        pendingSelectedFileRead?.cancel()
        if let applicationWillTerminateObserver {
            NotificationCenter.default.removeObserver(applicationWillTerminateObserver)
        }
    }

    var entries: [ClipboardEntry] {
        history.entries
    }

    var currentEntry: ClipboardEntry? {
        history.currentEntry
    }

    var previousEntry: ClipboardEntry? {
        history.previousEntry
    }

    var fileLabels: ClipboardFileLabels {
        ClipboardEntryDisplay.resolveFileLabels(
            previous: previousEntry,
            current: currentEntry
        )
    }

    var canDiff: Bool {
        history.canDiff
    }

    var isMonitoring: Bool {
        get {
            history.isMonitoring
        }
        set {
            guard newValue != history.isMonitoring else { return }

            objectWillChange.send()
            cancelPendingFileRead()
            lastRequestedChangeCount = clipboard.changeCount

            if newValue {
                history.resume(currentChangeCount: lastRequestedChangeCount)
            } else {
                history.pause()
            }
        }
    }

    var statusText: String {
        history.statusText
    }

    var selectedExternalDiffTool: ExternalDiffToolChoice? {
        guard let selectedPath = externalDiffSettings.selectedExecutablePath else {
            return nil
        }
        return externalDiffTools.first { choice in
            choice.executableURL.path == selectedPath
        }
    }

    var diffViewerName: String {
        selectedExternalDiffTool?.displayName ?? "Built-in viewer"
    }

    var isFinderIntegrationEnabled: Bool {
        FIFinderSyncController.isExtensionEnabled
    }

    func showDiff() {
        guard let previousEntry, let currentEntry else {
            lastError = "Copy two text values or files first."
            NSSound.beep()
            return
        }

        var fallbackError: String?
        if let selectedExternalDiffTool,
           confirmExternalDiffRisk() {
            let labels = DiffEngine.makeLabels(
                previous: previousEntry,
                current: currentEntry
            )
            if externalDiffLauncher.tryLaunch(
                selectedExternalDiffTool,
                previous: previousEntry,
                current: currentEntry,
                labels: labels
            ) {
                lastError = nil
                return
            }
            fallbackError = "Could not open \(selectedExternalDiffTool.displayName). Showing the built-in viewer."
        }

        activeDiff = DiffEngine.makeDocument(previous: previousEntry, current: currentEntry)
        lastError = fallbackError

        if diffWindowController == nil {
            diffWindowController = DiffWindowController(controller: self)
        }
        diffWindowController?.show()
    }

    func selectExternalDiffTool(_ choice: ExternalDiffToolChoice?) {
        objectWillChange.send()
        externalDiffSettings.selectedExecutablePath = choice?.executableURL.path
        externalDiffSettingsStore.save(externalDiffSettings)
        lastError = nil
    }

    func showShortcutSettings() {
        if shortcutSettingsWindowController == nil {
            shortcutSettingsWindowController = ShortcutSettingsWindowController(controller: self)
        }
        shortcutSettingsWindowController?.show()
    }

    @discardableResult
    func setGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard hotKeyController?.updateShortcut(shortcut) == true else {
            isGlobalShortcutAvailable = hotKeyController?.isRegistered ?? false
            lastError = "That keyboard shortcut is already in use."
            NSSound.beep()
            return false
        }

        globalShortcut = shortcut
        globalShortcutSettingsStore.save(shortcut)
        isGlobalShortcutAvailable = true
        lastError = nil
        return true
    }

    func showFinderIntegrationSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func compareSelectedFiles(_ fileURLs: [URL]) {
        guard fileURLs.count == 2 else {
            lastError = "Choose exactly two text files to compare."
            NSSound.beep()
            return
        }

        cancelPendingFileRead()
        pendingSelectedFileRead?.cancel()
        lastRequestedChangeCount = clipboard.changeCount
        let fileReader = self.fileReader

        pendingSelectedFileRead = Task { [weak self] in
            let values = await fileReader.readValues(from: fileURLs)
            guard !Task.isCancelled else { return }
            self?.finishSelectedFileRead(values)
        }
    }

    func chooseExternalDiffTool() {
        let panel = NSOpenPanel()
        panel.title = "Choose a diff application"
        panel.message = "Choose a macOS application or executable that can compare two file paths."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        guard let choice = ExternalDiffToolDiscovery.choice(forSelectedURL: selectedURL) else {
            lastError = "That item is not an executable diff application."
            NSSound.beep()
            return
        }

        if !externalDiffTools.contains(where: { $0.id == choice.id }) {
            externalDiffTools.append(choice)
        }
        selectExternalDiffTool(choice)
    }

    func clearCapturedText() {
        cancelPendingFileRead()
        pendingSelectedFileRead?.cancel()
        pendingSelectedFileRead = nil
        objectWillChange.send()
        history.clearCapturedText()
        activeDiff = nil
        lastError = nil
    }

    func copyActiveDiff() {
        guard let activeDiff else {
            NSSound.beep()
            return
        }

        cancelPendingFileRead()
        clipboard.replaceText(DiffEngine.copyableDiff(for: activeDiff))
        lastRequestedChangeCount = clipboard.changeCount
        _ = history.apply(
            ClipboardObservation(
                changeCount: lastRequestedChangeCount,
                observedAt: Date(),
                content: .ownWrite
            )
        )
    }

    func showAbout() {
        AppAbout.show()
    }

    private func confirmExternalDiffRisk() -> Bool {
        guard !externalDiffSettings.plaintextWarningAcknowledged else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "External diff privacy notice"
        alert.informativeText = """
        External diff applications require ClipDiff to write the previous and current text to read-only plaintext files in its temporary folder. Clipboard text may contain passwords, tokens, or other secrets.

        ClipDiff attempts to delete these files after the comparison application closes, when ClipDiff quits, and on its next launch. Files may remain after a crash or power loss, and the chosen application may retain its own copies.
        """
        let continueButton = alert.addButton(withTitle: "Continue")
        let builtInButton = alert.addButton(withTitle: "Use Built-in Viewer")
        continueButton.keyEquivalent = ""
        builtInButton.keyEquivalent = "\r"

        NSApplication.shared.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        externalDiffSettings.plaintextWarningAcknowledged = true
        externalDiffSettingsStore.save(externalDiffSettings)
        return true
    }

    private func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                self.readPasteboardIfNeeded()
            }
        }
        timer?.tolerance = 0.15
    }

    private func readPasteboardIfNeeded() {
        guard history.isMonitoring else { return }

        let changeCount = clipboard.changeCount
        guard changeCount != lastRequestedChangeCount else { return }

        let observedAt = Date()
        supersedePendingFileRead(observedAt: observedAt)
        lastRequestedChangeCount = changeCount

        switch clipboard.readSnapshot() {
        case .text(let text):
            apply(
                ClipboardObservation(
                    changeCount: changeCount,
                    observedAt: observedAt,
                    content: .value(CapturedClipboardValue(text: text))
                )
            )

        case .fileURLs(let fileURLs):
            guard (1...2).contains(fileURLs.count) else {
                apply(
                    ClipboardObservation(
                        changeCount: changeCount,
                        observedAt: observedAt,
                        content: .nonText
                    )
                )
                return
            }
            beginFileRead(fileURLs, changeCount: changeCount, observedAt: observedAt)

        case .explicitClear:
            apply(
                ClipboardObservation(
                    changeCount: changeCount,
                    observedAt: observedAt,
                    content: .explicitClear
                )
            )

        case .nonText:
            apply(
                ClipboardObservation(
                    changeCount: changeCount,
                    observedAt: observedAt,
                    content: .nonText
                )
            )
        }
    }

    private func beginFileRead(
        _ fileURLs: [URL],
        changeCount: Int,
        observedAt: Date
    ) {
        pendingFileReadChangeCount = changeCount
        let fileReader = self.fileReader

        pendingFileRead = Task { [weak self] in
            let values = await fileReader.readValues(from: fileURLs)
            guard !Task.isCancelled else { return }
            self?.finishFileRead(
                values,
                changeCount: changeCount,
                observedAt: observedAt
            )
        }
    }

    private func finishFileRead(
        _ values: [CopiedFileText],
        changeCount: Int,
        observedAt: Date
    ) {
        guard pendingFileReadChangeCount == changeCount,
              lastRequestedChangeCount == changeCount,
              clipboard.changeCount == changeCount,
              history.isMonitoring else {
            return
        }

        pendingFileRead = nil
        pendingFileReadChangeCount = nil

        let content: ClipboardObservationContent
        switch values.count {
        case 1:
            content = .value(values[0].capturedValue)
        case 2:
            content = .pair(
                previous: values[0].capturedValue,
                current: values[1].capturedValue
            )
        default:
            content = .nonText
        }

        apply(
            ClipboardObservation(
                changeCount: changeCount,
                observedAt: observedAt,
                content: content
            )
        )
    }

    private func finishSelectedFileRead(_ values: [CopiedFileText]) {
        pendingSelectedFileRead = nil

        guard values.count == 2 else {
            lastError = "The selected files could not be read."
            NSSound.beep()
            return
        }

        history.replaceComparisonPair(
            previous: values[0].capturedValue,
            current: values[1].capturedValue,
            capturedAt: Date()
        )
        activeDiff = nil
        lastError = nil
        objectWillChange.send()
        showDiff()
    }

    private func apply(_ observation: ClipboardObservation) {
        let change = history.apply(observation)

        switch change {
        case .accepted:
            lastError = nil
            objectWillChange.send()

        case .removedByRecentClear:
            activeDiff = nil
            lastError = nil
            objectWillChange.send()

        case .none:
            break
        }
    }

    private func cancelPendingFileRead() {
        pendingFileRead?.cancel()
        pendingFileRead = nil
        pendingFileReadChangeCount = nil
    }

    private func supersedePendingFileRead(observedAt: Date) {
        guard let pendingChangeCount = pendingFileReadChangeCount else { return }

        cancelPendingFileRead()
        _ = history.apply(
            ClipboardObservation(
                changeCount: pendingChangeCount,
                observedAt: observedAt,
                content: .nonText
            )
        )
    }
}
