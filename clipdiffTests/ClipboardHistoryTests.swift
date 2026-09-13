import XCTest
@testable import ClipDiffCore

final class ClipboardHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testCapturesLastTwoTextValues() {
        let history = ClipboardHistory()

        XCTAssertEqual(history.apply(text(1, "old text")), .accepted)
        XCTAssertEqual(history.apply(text(2, "new text")), .accepted)

        XCTAssertEqual(history.previousEntry?.text, "old text")
        XCTAssertEqual(history.currentEntry?.text, "new text")
        XCTAssertTrue(history.canDiff)
        XCTAssertEqual(history.statusText, "Ready to diff")
    }

    func testCapturesIdenticalConsecutiveCopiesAsComparisonPair() {
        let history = ClipboardHistory()

        history.apply(text(1, "same text"))
        history.apply(text(2, "same text"))

        XCTAssertEqual(history.entries.map(\.text), ["same text", "same text"])
        let document = DiffEngine.makeDocument(
            previous: history.previousEntry!,
            current: history.currentEntry!
        )
        XCTAssertFalse(document.summary.hasDifferences)
        XCTAssertEqual(document.summary.label, "No differences")
    }

    func testTextPairAtomicallyReplacesHistoryInClipboardOrder() {
        let history = ClipboardHistory()
        history.apply(text(1, "discarded"))

        let previous = CapturedClipboardValue(
            text: "old contents",
            sourceFileName: "old.txt",
            sourceFilePath: "/files/old.txt"
        )
        let current = CapturedClipboardValue(
            text: "new contents",
            sourceFileName: "new.txt",
            sourceFilePath: "/files/new.txt"
        )
        let change = history.apply(observation(
            2,
            content: .pair(previous: previous, current: current)
        ))

        XCTAssertEqual(change, .accepted)
        XCTAssertEqual(history.entries.map(\.text), ["new contents", "old contents"])
        XCTAssertEqual(history.previousEntry?.sourceFileName, "old.txt")
        XCTAssertEqual(history.currentEntry?.sourceFileName, "new.txt")
        XCTAssertEqual(history.previousEntry?.sourceFilePath, "/files/old.txt")
        XCTAssertEqual(history.currentEntry?.sourceFilePath, "/files/new.txt")
    }

    func testWhitespaceOnlyTextIsAccepted() {
        let history = ClipboardHistory()

        history.apply(text(1, " \t\r\n"))

        XCTAssertEqual(history.currentEntry?.text, " \t\r\n")
    }

    func testNonTextObservationLeavesHistoryUntouched() {
        let history = ClipboardHistory()
        history.apply(text(1, "kept"))

        history.apply(observation(2, content: .nonText))

        XCTAssertEqual(history.entries.map(\.text), ["kept"])
    }

    func testPausedMonitoringLeavesHistoryUntouchedAndResumeSetsBaseline() {
        let history = ClipboardHistory()
        history.apply(text(1, "first"))
        history.pause()

        XCTAssertEqual(history.apply(text(2, "ignored")), .none)
        history.resume(currentChangeCount: 8)
        XCTAssertEqual(history.apply(text(8, "also ignored")), .none)
        XCTAssertEqual(history.apply(text(9, "accepted")), .accepted)

        XCTAssertEqual(history.entries.map(\.text), ["accepted", "first"])
    }

    func testRecentExplicitClearRemovesOnlyLatestEligibleEntry() {
        let history = ClipboardHistory()
        history.apply(text(1, "older"))
        history.apply(text(2, "possibly sensitive", seconds: 30))

        let change = history.apply(observation(
            3,
            seconds: 45,
            content: .explicitClear
        ))

        XCTAssertEqual(change, .removedByRecentClear)
        XCTAssertEqual(history.entries.map(\.text), ["older"])
    }

    func testClearOutsideRecentWindowLeavesHistoryUntouched() {
        let history = ClipboardHistory()
        history.apply(text(1, "kept"))

        let change = history.apply(observation(
            2,
            seconds: 61,
            content: .explicitClear
        ))

        XCTAssertEqual(change, .none)
        XCTAssertEqual(history.entries.map(\.text), ["kept"])
    }

    func testInterveningNonTextPreventsUnrelatedClear() {
        let history = ClipboardHistory()
        history.apply(text(1, "kept"))
        history.apply(observation(2, seconds: 1, content: .nonText))

        history.apply(observation(3, seconds: 2, content: .explicitClear))

        XCTAssertEqual(history.entries.map(\.text), ["kept"])
    }

    func testOwnWriteDoesNotEnterHistoryAndPreventsUnrelatedClear() {
        let history = ClipboardHistory()
        history.apply(text(1, "ordinary"))

        history.apply(observation(2, seconds: 1, content: .ownWrite))
        history.apply(observation(3, seconds: 2, content: .explicitClear))

        XCTAssertEqual(history.entries.map(\.text), ["ordinary"])
    }

    func testClearCapturedTextRemovesBothEntries() {
        let history = ClipboardHistory()
        history.apply(text(1, "first"))
        history.apply(text(2, "second"))

        history.clearCapturedText()

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(history.statusText, "Waiting for copied text")
    }

    func testExplicitComparisonPairWorksWhileMonitoringIsPaused() {
        let history = ClipboardHistory()
        history.apply(text(1, "discarded"))
        history.pause()

        history.replaceComparisonPair(
            previous: CapturedClipboardValue(
                text: "old",
                sourceFileName: "old.txt",
                sourceFilePath: "/tmp/old.txt"
            ),
            current: CapturedClipboardValue(
                text: "new",
                sourceFileName: "new.txt",
                sourceFilePath: "/tmp/new.txt"
            ),
            capturedAt: start
        )

        XCTAssertEqual(history.entries.map(\.text), ["new", "old"])
        XCTAssertEqual(history.previousEntry?.sourceFileName, "old.txt")
        XCTAssertEqual(history.currentEntry?.sourceFileName, "new.txt")
        XCTAssertTrue(history.canDiff)
        XCTAssertFalse(history.isMonitoring)
    }

    func testSingleFinderComparisonPreservesCapturedEntryAndDropsOlderEntry() throws {
        let history = ClipboardHistory()
        history.apply(text(1, "older"))
        history.apply(observation(2, seconds: 4, content: .value(CapturedClipboardValue(
            text: "captured original",
            sourceFileName: "settings.json",
            sourceFilePath: "/old/settings.json"
        ))))
        let captured = try XCTUnwrap(history.currentEntry)

        XCTAssertTrue(history.compareCurrentEntry(
            expectedID: captured.id,
            with: CapturedClipboardValue(
                text: "captured original",
                sourceFileName: "settings.json",
                sourceFilePath: "/new/settings.json"
            ),
            capturedAt: start.addingTimeInterval(10)
        ))

        XCTAssertEqual(history.previousEntry, captured)
        XCTAssertEqual(history.currentEntry?.text, "captured original")
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(DiffEngine.makeDocument(
            previous: history.previousEntry!, current: history.currentEntry!
        ).summary.label, "No differences")
        XCTAssertEqual(ClipboardEntryDisplay.resolveFileLabels(
            previous: history.previousEntry, current: history.currentEntry
        ), ClipboardFileLabels(previous: "old/settings.json", current: "new/settings.json"))

        history.apply(observation(3, seconds: 11, content: .explicitClear))
        XCTAssertEqual(history.entries.count, 2, "direct comparison cancels recent-clear eligibility")
    }

    func testSingleFinderComparisonRejectsAChangedCurrentIdentity() throws {
        let history = ClipboardHistory()
        history.apply(text(1, "same"))
        let firstID = try XCTUnwrap(history.currentEntry?.id)
        history.apply(text(2, "same"))

        XCTAssertFalse(history.compareCurrentEntry(
            expectedID: firstID,
            with: CapturedClipboardValue(text: "file"),
            capturedAt: start
        ))
        XCTAssertEqual(history.entries.map(\.text), ["same", "same"])
    }

    func testStartupChangeCountIsOnlyABaseline() {
        let history = ClipboardHistory(startupChangeCount: 42)

        history.apply(text(42, "pre-start value"))
        history.apply(text(43, "future value"))

        XCTAssertEqual(history.entries.map(\.text), ["future value"])
    }

    private func text(_ changeCount: Int, _ value: String, seconds: TimeInterval = 0) -> ClipboardObservation {
        observation(
            changeCount,
            seconds: seconds,
            content: .value(CapturedClipboardValue(text: value))
        )
    }

    private func observation(
        _ changeCount: Int,
        seconds: TimeInterval = 0,
        content: ClipboardObservationContent
    ) -> ClipboardObservation {
        ClipboardObservation(
            changeCount: changeCount,
            observedAt: start.addingTimeInterval(seconds),
            content: content
        )
    }
}
