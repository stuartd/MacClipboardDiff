import XCTest
@testable import ClipDiffCore

final class ClipboardHistoryTests: XCTestCase {
    func testCapturesLastTwoUniqueTextValues() {
        let clipboard = FakeClipboardTextStore()
        let history = ClipboardHistory(clipboard: clipboard)

        clipboard.copy("old text")
        XCTAssertTrue(history.readClipboardIfNeeded())

        clipboard.copy("new text")
        XCTAssertTrue(history.readClipboardIfNeeded())

        XCTAssertEqual(history.previousEntry?.text, "old text")
        XCTAssertEqual(history.currentEntry?.text, "new text")
        XCTAssertTrue(history.canDiff)
        XCTAssertEqual(history.statusText, "Ready to diff")
    }

    func testIgnoresDuplicateConsecutiveText() {
        let clipboard = FakeClipboardTextStore()
        let history = ClipboardHistory(clipboard: clipboard)

        clipboard.copy("same text")
        XCTAssertTrue(history.readClipboardIfNeeded())

        clipboard.copy("same text")
        XCTAssertFalse(history.readClipboardIfNeeded())

        XCTAssertEqual(history.entries.map(\.text), ["same text"])
        XCTAssertFalse(history.canDiff)
    }

    func testIgnoresEmptyAndNonTextClipboardChangesWithoutClearingHistory() {
        let clipboard = FakeClipboardTextStore()
        let history = ClipboardHistory(clipboard: clipboard)

        clipboard.copy("first")
        XCTAssertTrue(history.readClipboardIfNeeded())

        clipboard.copy("")
        XCTAssertFalse(history.readClipboardIfNeeded())

        clipboard.copy(nil)
        XCTAssertFalse(history.readClipboardIfNeeded())

        XCTAssertEqual(history.entries.map(\.text), ["first"])
    }

    func testPausedMonitoringLeavesHistoryUntouched() {
        let clipboard = FakeClipboardTextStore()
        let history = ClipboardHistory(clipboard: clipboard)

        clipboard.copy("first")
        XCTAssertTrue(history.readClipboardIfNeeded())

        history.isMonitoring = false
        clipboard.copy("second")
        XCTAssertFalse(history.readClipboardIfNeeded())

        XCTAssertEqual(history.entries.map(\.text), ["first"])
        XCTAssertEqual(history.statusText, "Monitoring paused")
    }

    func testReplacingClipboardDoesNotBecomeCapturedHistory() {
        let clipboard = FakeClipboardTextStore()
        let history = ClipboardHistory(clipboard: clipboard)

        clipboard.copy("before")
        XCTAssertTrue(history.readClipboardIfNeeded())

        clipboard.copy("after")
        XCTAssertTrue(history.readClipboardIfNeeded())

        let document = DiffEngine.makeDocument(
            previous: history.previousEntry!,
            current: history.currentEntry!
        )
        let copyableDiff = DiffEngine.copyableDiff(for: document)

        history.replaceClipboard(with: copyableDiff)

        XCTAssertFalse(history.readClipboardIfNeeded())
        XCTAssertEqual(history.entries.map(\.text), ["after", "before"])
        XCTAssertEqual(clipboard.replacedTexts, [copyableDiff])
    }
}

private final class FakeClipboardTextStore: ClipboardTextStore {
    private(set) var changeCount = 0
    private(set) var replacedTexts: [String] = []
    var text: String?

    func copy(_ text: String?) {
        self.text = text
        changeCount += 1
    }

    func replaceText(_ text: String) {
        self.text = text
        replacedTexts.append(text)
        changeCount += 1
    }
}
