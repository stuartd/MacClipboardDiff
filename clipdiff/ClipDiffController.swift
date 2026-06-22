import AppKit
import Combine
import Foundation

@MainActor
final class ClipDiffController: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var activeDiff: DiffDocument?
    @Published private(set) var lastError: String?
    @Published var viewMode: DiffViewMode = .sideBySide
    @Published var isMonitoring = true {
        didSet {
            if isMonitoring {
                lastChangeCount = NSPasteboard.general.changeCount
                lastError = nil
            }
        }
    }

    private let maxEntries = 2
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var diffWindowController: DiffWindowController?
    private var hotKeyController: HotKeyController?

    init() {
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

    var currentEntry: ClipboardEntry? {
        entries.first
    }

    var previousEntry: ClipboardEntry? {
        entries.dropFirst().first
    }

    var canDiff: Bool {
        previousEntry != nil && currentEntry != nil
    }

    var statusText: String {
        if !isMonitoring {
            return "Monitoring paused"
        }

        switch entries.count {
        case 0:
            return "Waiting for copied text"
        case 1:
            return "Copy one more text value"
        default:
            return "Ready to diff"
        }
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
        entries.removeAll()
        activeDiff = nil
        lastError = nil
    }

    func copyActiveDiff() {
        guard let activeDiff else {
            NSSound.beep()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiffEngine.copyableDiff(for: activeDiff), forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
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
        guard isMonitoring else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        guard pasteboard.availableType(from: [.string]) != nil,
              let copiedText = pasteboard.string(forType: .string),
              !copiedText.isEmpty else {
            return
        }

        guard copiedText != currentEntry?.text else { return }

        let entry = ClipboardEntry(text: copiedText, capturedAt: Date())
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        lastError = nil
    }
}
