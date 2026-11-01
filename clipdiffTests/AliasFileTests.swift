import Foundation
import XCTest
@testable import ClipDiffCore

final class AliasFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDiff.AliasTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAliasUsesTargetContentsAndMetadataInsteadOfAliasRecord() async throws {
        let alias = try file("source alias", "alias record is not text to compare")
        let target = try file("target ☃.txt", "target contents")
        let originalAliasData = try Data(contentsOf: alias)
        let values = await reader([alias: target]).readValues(from: [alias])
        XCTAssertEqual(values, [value(target, "target contents")])
        XCTAssertEqual(try Data(contentsOf: alias), originalAliasData)
    }

    func testAliasDetectionPrecedesBinaryExtensionClassification() throws {
        let alias = try file("misleading.zip", "alias record")
        let target = try file("source.txt", "text")
        XCTAssertEqual(reader([alias: target]).readFile(at: alias), value(target, "text"))
    }

    func testQuotedAndUnquotedAliasPathsWorkAsSingleCaptureAndPair() async throws {
        let first = try file("first alias", "first record")
        let second = try file("second alias", "second record")
        let old = try file("old.txt", "old contents")
        let new = try file("new.txt", "new contents")
        let reader = reader([first: old, second: new])
        for text in [first.path, "\"\(first.path)\""] {
            let content = await reader.readClipboardText(text)
            XCTAssertEqual(content, .value(value(old, "old contents").capturedValue))
        }
        for text in ["\(first.path)\n\(second.path)", "\"\(first.path)\"\r\n\"\(second.path)\"\r\n"] {
            let content = await reader.readClipboardText(text)
            XCTAssertEqual(content, .pair(
                previous: value(old, "old contents").capturedValue,
                current: value(new, "new contents").capturedValue
            ))
        }
    }

    func testMixedAliasAndRegularFilePairPreservesOrder() async throws {
        let alias = try file("alias", "record")
        let target = try file("target.txt", "old")
        let regular = try file("regular.txt", "new")
        let reader = reader([alias: target])
        let forward = await reader.readValues(from: [alias, regular])
        let reverse = await reader.readValues(from: [regular, alias])
        XCTAssertEqual(forward, [value(target, "old"), value(regular, "new")])
        XCTAssertEqual(reverse, [value(regular, "new"), value(target, "old")])
    }

    func testAliasTargetUsesExistingEmptySizeAndDirectoryFallbacks() throws {
        let alias = try file("alias", "record")
        let empty = try file("empty.txt", "")
        let large = try file("large.txt", "12345")
        let missing = directory.appendingPathComponent("missing.txt")
        for (target, expected) in [
            (empty, "empty.txt (empty file)"), (large, "large.txt (file too large)"),
            (missing, "missing.txt (file not found)"), (directory!, directory.lastPathComponent + " (directory)")
        ] {
            let result = reader([alias: target], limit: 4).readFile(at: alias)
            XCTAssertEqual(result, value(target, expected))
        }
    }

    func testUnresolvableAliasUsesAliasFallbackInsteadOfRecordContents() throws {
        let alias = try file("broken alias", "this record must not become captured text")
        let reader = CopiedFileTextReader(resolveAlias: { _ in throw CocoaError(.fileReadCorruptFile) })
        XCTAssertEqual(reader.readFile(at: alias), value(alias, "broken alias (file unreadable)"))
    }

    func testBinaryAliasTargetProvidesTargetFallbackAndReplacesCaptures() async throws {
        let alias = try file("binary alias", "record")
        let target = directory.appendingPathComponent("binary.txt")
        try Data([0, 1, 2]).write(to: target)
        let text = try file("source.txt", "contents")
        let reader = reader([alias: target])
        let values = await reader.readValues(from: [text, alias])
        XCTAssertEqual(values, [value(text, "contents"), value(target, "binary.txt (binary file)")])
        let history = ClipboardHistory()
        history.replaceComparisonPair(previous: CapturedClipboardValue(text: "old"), current: CapturedClipboardValue(text: "new"), capturedAt: Date())
        let content = await reader.readClipboardText("\(text.path)\n\(alias.path)")
        XCTAssertEqual(content, .pair(previous: value(text, "contents").capturedValue, current: value(target, "binary.txt (binary file)").capturedValue))
        XCTAssertEqual(history.apply(ClipboardObservation(changeCount: 1, observedAt: Date(), content: content)), .accepted)
        XCTAssertEqual(history.previousEntry?.text, "contents")
        XCTAssertEqual(history.currentEntry?.text, "binary.txt (binary file)")
    }

    func testAliasToKnownBinaryTargetUsesTargetNameFallback() throws {
        let alias = try file("alias", "record")
        let binary = try file("archive.zip", "even these text bytes must become a binary fallback")
        XCTAssertEqual(reader([alias: binary]).readFile(at: alias), value(binary, "archive.zip (binary file)"))
    }

    func testEightAliasChainResolvesAndNinthAliasIsRejected() throws {
        let aliases = try (0..<9).map { try file("alias\($0)", "record") }
        let target = try file("target.txt", "contents")
        var links: [URL: URL] = [:]
        for index in 0..<8 { links[aliases[index]] = aliases[index + 1] }
        links[aliases[8]] = target
        let reader = reader(links)
        XCTAssertEqual(reader.readFile(at: aliases[1]), value(target, "contents"))
        XCTAssertEqual(reader.readFile(at: aliases[0]), value(aliases[0], "alias0 (file unreadable)"))
    }

    func testSelfAliasAndAliasCycleAreRejected() throws {
        let first = try file("first", "record")
        let second = try file("second", "record")
        for links in [[first: first], [first: second, second: first]] {
            XCTAssertEqual(reader(links).readFile(at: first), value(first, "first (file unreadable)"))
        }
    }

    func testNonFileTargetIsRejectedWithoutOpeningAnything() throws {
        let alias = try file("alias", "record")
        let remote = try XCTUnwrap(URL(string: "https://example.com/file.txt"))
        XCTAssertEqual(reader([alias: remote]).readFile(at: alias), value(alias, "alias (file unreadable)"))
    }

    func testTargetPathIsUsedForSameFileAndFilenameDisambiguation() throws {
        let alias = try file("alias", "record")
        let target = try file("source.txt", "contents")
        let resolved = try XCTUnwrap(reader([alias: target]).readFile(at: alias))
        let history = ClipboardHistory()
        history.apply(ClipboardObservation(changeCount: 1, observedAt: Date(), content: .value(resolved.capturedValue)))
        XCTAssertFalse(history.compareCurrentEntry(
            expectedID: try XCTUnwrap(history.currentEntry?.id), with: resolved.capturedValue, capturedAt: Date()
        ))
        XCTAssertTrue(FinderCaptureIdentity.isSamePath(target, sourceFilePath: history.currentEntry?.sourceFilePath))
    }

    #if os(macOS)
    func testRealFinderAliasResolvesWithoutRewritingTheAlias() async throws {
        let target = try file("real target.txt", "real target contents").resolvingSymlinksInPath()
        let alias = directory.appendingPathComponent("real alias")
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        XCTAssertEqual(try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile, true)
        let before = try Data(contentsOf: alias)
        let reader = CopiedFileTextReader()
        let values = await reader.readValues(from: [alias])
        XCTAssertEqual(values, [value(target, "real target contents")])
        let content = await reader.readClipboardText("\"\(alias.path)\"")
        XCTAssertEqual(content, .value(value(target, "real target contents").capturedValue))
        XCTAssertEqual(try Data(contentsOf: alias), before)
    }

    func testRealFinderAliasToBinaryTargetHasTargetFallback() async throws {
        let target = directory.appendingPathComponent("real.zip")
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: target)
        let alias = directory.appendingPathComponent("real binary alias")
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        let values = await CopiedFileTextReader().readValues(from: [alias])
        XCTAssertEqual(values.map(\.text), ["real.zip (binary file)"])
        XCTAssertEqual(values.first?.fileName, "real.zip")
    }

    func testRealBrokenFinderAliasDoesNotCaptureBookmarkBytes() throws {
        let target = try file("removed target.txt", "contents")
        let alias = directory.appendingPathComponent("broken real alias")
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        try FileManager.default.removeItem(at: target)
        let result = CopiedFileTextReader().readFile(at: alias)
        // macOS may reject the bookmark or return its now-missing saved URL.
        // Both outcomes must be a reason label, never the alias record's bytes.
        let fallback = try XCTUnwrap(result)
        if fallback.filePath == alias.standardizedFileURL.path {
            XCTAssertEqual(fallback, value(alias, "broken real alias (file unreadable)"))
        } else {
            XCTAssertEqual(fallback, value(target, "removed target.txt (file not found)"))
        }
    }
    #endif

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func reader(_ targets: [URL: URL], limit: Int = CopiedFileTextReader.defaultMaximumTextFileBytes) -> CopiedFileTextReader {
        CopiedFileTextReader(maximumTextFileBytes: limit, resolveAlias: { targets[$0] })
    }

    private func value(_ file: URL, _ text: String) -> CopiedFileText {
        CopiedFileText(text: text, fileName: file.lastPathComponent, filePath: file.standardizedFileURL.path)
    }
}
