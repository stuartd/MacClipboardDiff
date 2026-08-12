import Foundation

final class ClipboardHistory {
    private(set) var entries: [ClipboardEntry] = []
    private(set) var lastError: String?

    private let clipboard: ClipboardTextStore
    private let maxEntries: Int
    private var lastChangeCount: Int

    var isMonitoring = true {
        didSet {
            if isMonitoring {
                lastChangeCount = clipboard.changeCount
                lastError = nil
            }
        }
    }

    init(clipboard: ClipboardTextStore, maxEntries: Int = 2) {
        self.clipboard = clipboard
        self.maxEntries = max(2, maxEntries)
        lastChangeCount = clipboard.changeCount
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

    @discardableResult
    func readClipboardIfNeeded() -> Bool {
        guard isMonitoring else { return false }
        guard clipboard.changeCount != lastChangeCount else { return false }

        lastChangeCount = clipboard.changeCount

        guard let copiedText = clipboard.text, !copiedText.isEmpty else {
            return false
        }

        let entry = ClipboardEntry(text: copiedText, capturedAt: Date())
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        lastError = nil
        return true
    }

    func clearCapturedText() {
        entries.removeAll()
        lastError = nil
    }

    func replaceClipboard(with text: String) {
        clipboard.replaceText(text)
        lastChangeCount = clipboard.changeCount
    }
}
