import XCTest
@testable import ClipDiffCore

final class DiffEngineTests: XCTestCase {
    func testBuildsSideBySideRowsForChangedAndInsertedLines() {
        let previous = entry("alpha\nbravo\ncharlie")
        let current = entry("alpha\nbravo changed\ncharlie\ndelta")

        let document = DiffEngine.makeDocument(previous: previous, current: current)

        XCTAssertEqual(document.summary.unchanged, 2)
        XCTAssertEqual(document.summary.changed, 1)
        XCTAssertEqual(document.summary.inserted, 1)
        XCTAssertEqual(document.summary.removed, 0)
        XCTAssertEqual(document.summary.label, "1 changed line, 1 added line")

        let changedRow = document.rows.first { $0.kind == .changed }
        XCTAssertEqual(changedRow?.oldLineNumber, 2)
        XCTAssertEqual(changedRow?.newLineNumber, 2)
        XCTAssertEqual(changedRow?.oldText, "bravo")
        XCTAssertEqual(changedRow?.newText, "bravo changed")

        let insertedRow = document.rows.first { $0.kind == .inserted }
        XCTAssertEqual(insertedRow?.oldLineNumber, nil)
        XCTAssertEqual(insertedRow?.newLineNumber, 4)
        XCTAssertEqual(insertedRow?.newText, "delta")
    }

    func testBuildsRowsForRemovedLines() {
        let previous = entry("alpha\nbravo\ncharlie")
        let current = entry("alpha\ncharlie")

        let document = DiffEngine.makeDocument(previous: previous, current: current)

        XCTAssertEqual(document.summary.unchanged, 2)
        XCTAssertEqual(document.summary.changed, 0)
        XCTAssertEqual(document.summary.inserted, 0)
        XCTAssertEqual(document.summary.removed, 1)
        XCTAssertEqual(document.summary.label, "1 removed line")

        let removedRow = document.rows.first { $0.kind == .removed }
        XCTAssertEqual(removedRow?.oldLineNumber, 2)
        XCTAssertEqual(removedRow?.newLineNumber, nil)
        XCTAssertEqual(removedRow?.oldText, "bravo")
    }

    func testCopyableDiffUsesReadableUnifiedMarkers() {
        let previous = entry("same\nold")
        let current = entry("same\nnew")
        let document = DiffEngine.makeDocument(previous: previous, current: current)

        let diff = DiffEngine.copyableDiff(for: document)

        XCTAssertTrue(diff.contains("--- Previous clipboard"))
        XCTAssertTrue(diff.contains("+++ Current clipboard"))
        XCTAssertTrue(diff.contains("  same"))
        XCTAssertTrue(diff.contains("- old"))
        XCTAssertTrue(diff.contains("+ new"))
    }

    func testSummaryLabelIncludesLineUnits() {
        let summary = DiffSummary(inserted: 15, removed: 2, changed: 1, unchanged: 0)

        XCTAssertEqual(summary.label, "1 changed line, 15 added lines, 2 removed lines")
    }

    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(text: text, capturedAt: Date(timeIntervalSince1970: 0))
    }
}
