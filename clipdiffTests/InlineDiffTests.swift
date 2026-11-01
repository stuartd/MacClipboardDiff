import XCTest
@testable import ClipDiffCore

final class InlineDiffTests: XCTestCase {
    func testWindowsAcceptanceSpans() {
        let cases: [(String, String, Bool, String, String)] = [
            ("timeout = 30", "timeout = 60", false, "3", "6"),
            ("x = 12; y = 34", "x = 92; y = 38", false, "1|4", "9|8"),
            ("return value;", "return new_value;", false, "", "new_"),
            ("return new_value;", "return value;", false, "new_", ""),
            ("a\tb", "a b", false, "\t", " "),
            ("a\tb", "a  b", true, "", ""),
            ("a b", "ab", true, " ", ""),
            ("\t let  total = 30  ", "let total\t= 60", true, "3", "6"),
            ("👩🏽‍💻", "👨🏻‍💻", false, "👩🏽‍💻", "👨🏻‍💻"),
            ("e\u{301}", "o\u{301}", false, "e\u{301}", "o\u{301}"),
            ("\t👩🏽‍💻\t30", "\t👩🏽‍💻\t60", false, "3", "6"),
            ("", "new", false, "", "new"),
            ("new", "", false, "new", ""),
            ("a \t b", "ab", true, " \t ", "")
        ]
        for (old, new, ignoreSpacing, oldSpans, newSpans) in cases {
            let row = highlight(old, new, ignoreSpacing: ignoreSpacing)
            XCTAssertEqual(spans(old, row.oldHighlights).joined(separator: "|"), oldSpans, old)
            XCTAssertEqual(spans(new, row.newHighlights).joined(separator: "|"), newSpans, new)
            XCTAssertEqual(row.oldText, old)
            XCTAssertEqual(row.newText, new)
            assertRanges(old, row.oldHighlights)
            assertRanges(new, row.newHighlights)
        }
    }

    func testExactSpacingPreservesUnchangedWords() {
        let row = highlight("\t let  total = 30  ", "let total\t= 60")
        XCTAssertEqual(spans(row.oldText!, row.oldHighlights).joined(separator: "|"), "\t | | |3|  ")
        XCTAssertEqual(spans(row.newText!, row.newHighlights).joined(separator: "|"), "\t|6")
    }

    func testEqualAndUnpairedLinesHaveNoSpans() {
        for (old, new) in [("same\nold", "same"), ("same", "same\nnew"), ("same", "same")] {
            for row in compare(old, new).rows {
                XCTAssertTrue(row.oldHighlights.isEmpty)
                XCTAssertTrue(row.newHighlights.isEmpty)
            }
        }
    }

    func testIgnoreSpacingMatchesLinesAndSpansWithoutChangingSourceOrCopy() {
        let old = " \ta\t b  \n\t30"
        let new = "a b\n 60 "
        let document = compare(old, new, ignoreSpacing: true)
        XCTAssertEqual(document.rows.map(\.kind), [.equal, .changed])
        XCTAssertEqual(document.summary.changed, 1)
        XCTAssertEqual(document.summary.unchanged, 1)
        XCTAssertEqual(document.rows[0].oldText, " \ta\t b  ")
        XCTAssertEqual(document.rows[0].newText, "a b")
        XCTAssertEqual(spans(document.rows[1].oldText!, document.rows[1].oldHighlights), ["3"])
        XCTAssertEqual(document.previous.text, old)
        XCTAssertEqual(document.current.text, new)
        XCTAssertEqual(DiffEngine.copyableDiff(for: document),
            "--- Previous clipboard\n+++ Current clipboard\n   \ta\t b  \n- \t30\n+  60 ")
    }

    func testIgnoreSpacingDoesNotIgnoreMissingWordSeparatorsOrNewlines() {
        XCTAssertTrue(compare("a b", "ab", ignoreSpacing: true).summary.hasDifferences)
        XCTAssertEqual(compare("a", "a\n", ignoreSpacing: true).rows.map(\.kind), [.equal, .inserted])
        XCTAssertEqual(compare(" \t ", "\t", ignoreSpacing: true).rows.map(\.kind), [.equal])
        XCTAssertTrue(compare("a\nb", "a b", ignoreSpacing: true).summary.hasDifferences)
        XCTAssertEqual(compare("a\u{a0}b", " a  b ", ignoreSpacing: true).rows.map(\.kind), [.equal])
    }

    func testRecompareRestoresExactModeAndPreservesSnapshotAndResolvedLabels() {
        let old = ClipboardEntry(text: "  same\n30", capturedAt: Date(), sourceFileName: "config.txt", sourceFilePath: "/old/config.txt")
        let new = ClipboardEntry(text: "same  \n60", capturedAt: Date(), sourceFileName: "config.txt", sourceFilePath: "/new/config.txt")
        let exact = DiffEngine.makeDocument(previous: old, current: new)
        let ignored = DiffEngine.recompare(exact, ignoreSpacing: true)
        let restored = DiffEngine.recompare(ignored, ignoreSpacing: false)
        XCTAssertEqual(exact.rows.map(\.kind), [.changed, .changed])
        XCTAssertEqual(ignored.rows.map(\.kind), [.equal, .changed])
        XCTAssertEqual(restored.rows.map(\.kind), exact.rows.map(\.kind))
        XCTAssertEqual(restored.rows.map(\.oldHighlights), exact.rows.map(\.oldHighlights))
        XCTAssertEqual(DiffEngine.copyableDiff(for: restored), DiffEngine.copyableDiff(for: exact))
        XCTAssertEqual(ignored.labels, exact.labels)
        XCTAssertEqual(restored.labels, exact.labels)
        XCTAssertEqual(restored.createdAt, exact.createdAt)
        XCTAssertEqual(restored.previous.text, old.text)
        XCTAssertEqual(restored.current.text, new.text)
        XCTAssertNil(restored.previous.sourceFilePath)
        XCTAssertNil(restored.current.sourceFilePath)
    }

    func testAdjacentChangesMergeAndTiesMatchWindows() {
        let row = highlight("a!b", "b!a")
        XCTAssertEqual(row.oldHighlights, [HighlightRange(start: 0, end: 2)])
        XCTAssertEqual(row.newHighlights, [HighlightRange(start: 1, end: 3)])
    }

    func testUnicodeComparisonIsOrdinalNotCanonicallyNormalized() {
        for ignoreSpacing in [false, true] {
            let document = compare("é", "e\u{301}", ignoreSpacing: ignoreSpacing)
            XCTAssertEqual(document.rows.map(\.kind), [.changed])
            XCTAssertEqual(document.rows[0].oldHighlights, [HighlightRange(start: 0, end: 1)])
            XCTAssertEqual(document.rows[0].newHighlights, [HighlightRange(start: 0, end: 1)])
        }
    }

    func testDifficultPairRetainsMatchingEdges() {
        let row = highlight("same " + String(repeating: "a", count: 400) + " end", "same " + String(repeating: "b", count: 400) + " end")
        XCTAssertEqual(row.oldHighlights, [HighlightRange(start: 5, end: 405)])
        XCTAssertEqual(row.newHighlights, [HighlightRange(start: 5, end: 405)])
    }

    func testUtf8ByteLimitFallsBackToLineHighlightingWithoutChangingText() {
        let old = String(repeating: "😀", count: 2048)
        XCTAssertFalse(highlight(old, String(repeating: "a", count: 8192)).oldHighlights.isEmpty)
        let new = String(repeating: "a", count: 8193)
        let row = highlight(old, new)
        XCTAssertTrue(row.oldHighlights.isEmpty)
        XCTAssertTrue(row.newHighlights.isEmpty)
        XCTAssertEqual(row.kind, .changed)
        XCTAssertEqual(row.oldText, old)
        XCTAssertEqual(row.newText, new)
    }

    func testSharedWorkBudgetMatchesWindowsAndResetsPerDocument() {
        let old = String(repeating: "a", count: 8192)
        let new = String(repeating: "b", count: 8192)
        let document = compare(Array(repeating: old, count: 125).joined(separator: "\n"), Array(repeating: new, count: 125).joined(separator: "\n"))
        XCTAssertEqual(document.rows.filter { !$0.oldHighlights.isEmpty }.count, 122)
        XCTAssertFalse(document.rows[121].oldHighlights.isEmpty)
        XCTAssertTrue(document.rows[122].oldHighlights.isEmpty)
        XCTAssertEqual(document.summary.changed, 125)
        XCTAssertTrue(document.rows.allSatisfy { $0.oldText == old && $0.newText == new })
        XCTAssertFalse(compare(old, new).rows[0].oldHighlights.isEmpty)
    }

    func testRandomExactSpansLeaveIdenticalUnhighlightedBytes() {
        var seed: UInt64 = 814
        func next(_ count: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(count))
        }
        let pieces = ["foo", "bar", " ", "  ", "\t", "=", "!", "_", "9", "é", "e\u{301}", "👩🏽‍💻", "中"]
        func text() -> String { (0..<(1 + next(24))).map { _ in pieces[next(pieces.count)] }.joined() }
        for _ in 0..<500 {
            let old = text()
            let new = text()
            let row = highlight(old, new)
            assertRanges(old, row.oldHighlights)
            assertRanges(new, row.newHighlights)
            XCTAssertEqual(Array(remaining(old, row.oldHighlights).utf8), Array(remaining(new, row.newHighlights).utf8))
        }
    }

    func testSwappingInputsReversesInsertionAndDeletionSpans() {
        let forward = highlight("return value;", "return new_value;")
        let reverse = highlight("return new_value;", "return value;")
        XCTAssertEqual(forward.oldHighlights, reverse.newHighlights)
        XCTAssertEqual(forward.newHighlights, reverse.oldHighlights)
    }

    func testDisplaySlicesExpandTabsAfterGraphemeMappingAndKeepMarkupLiteral() {
        let source = "\t👩🏽‍💻\t30 <tag>& **text**"
        let slices = DiffTextFormatting.slices(source, highlights: [HighlightRange(start: 2, end: 4)])
        XCTAssertEqual(slices, [
            DiffTextSlice(text: "    👩🏽‍💻", highlighted: false),
            DiffTextSlice(text: "    3", highlighted: true),
            DiffTextSlice(text: "0 <tag>& **text**", highlighted: false)
        ])
        XCTAssertEqual(slices.map(\.text).joined(), source.replacingOccurrences(of: "\t", with: "    "))
    }

    func testDisplaySlicesNeverSplitCombiningMarksAndHandleEmptyText() {
        XCTAssertEqual(DiffTextFormatting.slices("e\u{301}!", highlights: [HighlightRange(start: 0, end: 1)]), [
            DiffTextSlice(text: "e\u{301}", highlighted: true), DiffTextSlice(text: "!", highlighted: false)
        ])
        XCTAssertEqual(DiffTextFormatting.slices(nil, highlights: []), [DiffTextSlice(text: "", highlighted: false)])
    }

    private func compare(_ old: String, _ new: String, ignoreSpacing: Bool = false) -> DiffDocument {
        DiffEngine.makeDocument(
            previous: ClipboardEntry(text: old, capturedAt: Date()),
            current: ClipboardEntry(text: new, capturedAt: Date()), ignoreSpacing: ignoreSpacing
        )
    }

    private func highlight(_ old: String, _ new: String, ignoreSpacing: Bool = false) -> DiffRow {
        var inline = InlineDiff(ignoreSpacing: ignoreSpacing)
        return inline.highlight(DiffRow(oldLineNumber: 1, newLineNumber: 1, oldText: old, newText: new, kind: .changed))
    }

    private func spans(_ text: String, _ ranges: [HighlightRange]) -> [String] {
        let characters = Array(text)
        return ranges.map { String(characters[$0.start..<$0.end]) }
    }

    private func remaining(_ text: String, _ ranges: [HighlightRange]) -> String {
        String(text.enumerated().filter { index, _ in !ranges.contains { index >= $0.start && index < $0.end } }.map(\.element))
    }

    private func assertRanges(_ text: String, _ ranges: [HighlightRange], file: StaticString = #filePath, line: UInt = #line) {
        var previousEnd = -1
        for range in ranges {
            XCTAssertGreaterThan(range.start, previousEnd, file: file, line: line)
            XCTAssertGreaterThan(range.end, range.start, file: file, line: line)
            XCTAssertLessThanOrEqual(range.end, text.count, file: file, line: line)
            previousEnd = range.end
        }
    }
}
