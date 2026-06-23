import AppKit
import Combine
import Foundation

@MainActor
final class ClipDiffController: ObservableObject {
    @Published private(set) var activeDiff: DiffDocument?
    @Published private(set) var lastError: String?
    @Published var viewMode: DiffViewMode = .sideBySide

    private let history: ClipboardHistory
    private var timer: Timer?
    private var diffWindowController: DiffWindowController?
    private var hotKeyController: HotKeyController?

    convenience init() {
        self.init(history: ClipboardHistory(clipboard: SystemClipboardTextStore()))
    }

    init(history: ClipboardHistory) {
        self.history = history

        startMonitoring()
        hotKeyController = HotKeyController { [weak self] in
            Task { @MainActor in
                self?.showDiff()
            }
        }

        if hotKeyController?.isRegistered == false {
            lastError = "Global shortcut could not be registered."
        }
    }

    deinit {
        timer?.invalidate()
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
            objectWillChange.send()
            history.isMonitoring = newValue
        }
    }

    var statusText: String {
        history.statusText
    }

    func showDiff() {
        guard let previousEntry, let currentEntry else {
            lastError = "Copy two different text values first."
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

        history.replaceClipboard(with: DiffEngine.copyableDiff(for: activeDiff))
    }

    private func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let controller = self else { return }

            Task { @MainActor in
                controller.readPasteboardIfNeeded()
            }
        }
        timer?.tolerance = 0.15
    }

    private func readPasteboardIfNeeded() {
        if history.readClipboardIfNeeded() {
            objectWillChange.send()
            lastError = nil
        }
    }
}
