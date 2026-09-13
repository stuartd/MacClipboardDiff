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
    private let globalShortcutValidator = GlobalShortcutValidator()
    private let externalDiffSettingsStore: ExternalDiffSettingsStore
    private let externalDiffLauncher: ExternalDiffLauncher
    private var externalDiffSettings: ExternalDiffSettings
    private var lastRequestedChangeCount: Int
    private var pendingFileReadChangeCount: Int?
    private var pendingFileRead: Task<Void, Never>?
    private var pendingSelectedFileRead: Task<Void, Never>?
    private var singleFileRequestState = FinderSingleFileRequestState()
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
        lastError = hotKeyController.lastError?.message

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
            cancelPendingFinderRead()
            lastRequestedChangeCount = clipboard.changeCount

            if newValue {
                history.resume(currentChangeCount: lastRequestedChangeCount)
            } else {
                history.pause()
            }
        }
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
    func setGlobalShortcut(_ shortcut: GlobalShortcut) -> GlobalShortcutError? {
        if let error = shortcutValidationError(shortcut) {
            return error
        }
        guard hotKeyController?.updateShortcut(shortcut) == true else {
            isGlobalShortcutAvailable = hotKeyController?.isRegistered ?? false
            let error = hotKeyController?.lastError ?? .unavailable
            lastError = error.message
            NSSound.beep()
            return error
        }

        globalShortcut = shortcut
        globalShortcutSettingsStore.save(shortcut)
        isGlobalShortcutAvailable = true
        lastError = nil
        return nil
    }

    func shortcutValidationError(_ shortcut: GlobalShortcut) -> GlobalShortcutError? {
        globalShortcutValidator.error(for: shortcut)
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
        cancelPendingFinderRead()
        lastRequestedChangeCount = clipboard.changeCount
        let fileReader = self.fileReader

        pendingSelectedFileRead = Task { [weak self] in
            let values = await fileReader.readValues(from: fileURLs)
            guard !Task.isCancelled else { return }
            self?.finishSelectedFileRead(values)
        }
    }

    func compareWithCurrentCapture(_ fileURL: URL) {
        guard let capturedEntry = currentEntry else {
            presentNoCurrentCaptureMessage()
            return
        }
        guard Self.isRegularFile(fileURL) else {
            lastError = "Choose one regular file to compare."
            NSSound.beep()
            return
        }

        cancelPendingFileRead()
        cancelPendingFinderRead()
        lastRequestedChangeCount = clipboard.changeCount
        let token = singleFileRequestState.begin(
            currentEntryID: capturedEntry.id,
            pasteboardChangeCount: lastRequestedChangeCount,
            isMonitoring: history.isMonitoring
        )
        let fileReader = self.fileReader

        pendingSelectedFileRead = Task { [weak self] in
            let values = await fileReader.readValues(from: [fileURL])
            guard !Task.isCancelled else { return }
            self?.finishSingleSelectedFileRead(values, token: token)
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
        cancelPendingFinderRead()
        objectWillChange.send()
        history.clearCapturedText()
        activeDiff = nil
        lastError = nil
    }

    func copyActiveDiff() {
        cancelPendingFinderRead()
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
        cancelPendingFinderRead()
        supersedePendingFileRead(observedAt: observedAt)
        lastRequestedChangeCount = changeCount

        switch clipboard.readSnapshot() {
        case .text(let text):
            beginTextRead(text, changeCount: changeCount, observedAt: observedAt)

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

    private func beginTextRead(
        _ text: String,
        changeCount: Int,
        observedAt: Date
    ) {
        pendingFileReadChangeCount = changeCount
        let fileReader = self.fileReader

        pendingFileRead = Task { [weak self] in
            let fileValue = await fileReader.readValue(fromFullyQualifiedPath: text)
            guard !Task.isCancelled else { return }
            self?.finishTextRead(
                text,
                fileValue: fileValue,
                changeCount: changeCount,
                observedAt: observedAt
            )
        }
    }

    private func finishTextRead(
        _ text: String,
        fileValue: CopiedFileText?,
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
        apply(
            ClipboardObservation(
                changeCount: changeCount,
                observedAt: observedAt,
                content: .value(fileValue?.capturedValue ?? CapturedClipboardValue(text: text))
            )
        )
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

    private func finishSingleSelectedFileRead(
        _ values: [CopiedFileText],
        token: FinderSingleFileRequestState.Token
    ) {
        pendingSelectedFileRead = nil
        guard values.count == 1,
              singleFileRequestState.consumeIfValid(
                token,
                currentEntryID: currentEntry?.id,
                pasteboardChangeCount: clipboard.changeCount,
                isMonitoring: history.isMonitoring
              ),
              history.compareCurrentEntry(
                expectedID: token.expectedCurrentEntryID,
                with: values[0].capturedValue,
                capturedAt: Date()
              ) else {
            return
        }

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

    private func cancelPendingFinderRead() {
        pendingSelectedFileRead?.cancel()
        pendingSelectedFileRead = nil
        singleFileRequestState.cancel()
    }

    private func presentNoCurrentCaptureMessage() {
        cancelPendingFinderRead()
        let message = "Copy some text or a file while ClipDiff is monitoring, then try again."
        lastError = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              let isRegularFile = values.isRegularFile else {
            // Let the bounded reader produce its normal "file not found" or
            // "file unreadable" fallback when a selected file vanishes.
            return true
        }
        return isRegularFile
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
