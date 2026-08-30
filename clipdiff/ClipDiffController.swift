import AppKit
import Combine
import Foundation

@MainActor
final class ClipDiffController: ObservableObject {
    @Published private(set) var activeDiff: DiffDocument?
    @Published private(set) var lastError: String?
    @Published private(set) var isGlobalShortcutAvailable = true
    @Published var viewMode: DiffViewMode = .sideBySide

    private let clipboard: ClipboardStore
    private let fileReader: CopiedFileTextReader
    private let history: ClipboardHistory
    private var lastRequestedChangeCount: Int
    private var pendingFileReadChangeCount: Int?
    private var pendingFileRead: Task<Void, Never>?
    private var timer: Timer?
    private var diffWindowController: DiffWindowController?
    private var hotKeyController: HotKeyController?

    convenience init() {
        self.init(clipboard: SystemClipboardStore())
    }

    init(
        clipboard: ClipboardStore,
        fileReader: CopiedFileTextReader = CopiedFileTextReader()
    ) {
        self.clipboard = clipboard
        self.fileReader = fileReader
        history = ClipboardHistory(startupChangeCount: clipboard.changeCount)
        lastRequestedChangeCount = clipboard.changeCount

        startMonitoring()

        let hotKeyController = HotKeyController { [weak self] in
            Task { @MainActor in
                self?.showDiff()
            }
        }
        self.hotKeyController = hotKeyController
        isGlobalShortcutAvailable = hotKeyController.isRegistered
    }

    deinit {
        timer?.invalidate()
        pendingFileRead?.cancel()
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

    func showDiff() {
        guard let previousEntry, let currentEntry else {
            lastError = "Copy two text values or files first."
            NSSound.beep()
            return
        }

        activeDiff = DiffEngine.makeDocument(previous: previousEntry, current: currentEntry)
        lastError = nil

        if diffWindowController == nil {
            diffWindowController = DiffWindowController(controller: self)
        }
        diffWindowController?.show()
    }

    func clearCapturedText() {
        cancelPendingFileRead()
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
