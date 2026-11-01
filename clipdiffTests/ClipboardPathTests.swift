import Foundation
import XCTest
@testable import ClipDiffCore

final class ClipboardPathTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDiff.PathTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSinglePathWithOptionalQuotesAndTrailingNewline() async throws {
        let file = try write("snow ☃ with spaces.txt", "file contents")
        for text in [file.path, "\"\(file.path)\"", file.path + "\n", "\"\(file.path)\"\r\n"] {
            let content = await CopiedFileTextReader().readClipboardText(text)
            XCTAssertEqual(content, .value(value(file, "file contents")), text)
        }
    }

    func testTwoPathsPreserveClipboardOrderAcrossQuotingAndLineEndings() async throws {
        let first = try write("first.txt", "old contents")
        let second = try write("second.txt", "new contents")
        for separator in ["\n", "\r\n", "\r"] {
            for (older, newer) in [
                (first.path, second.path),
                ("\"\(first.path)\"", "\"\(second.path)\""),
                (first.path, "\"\(second.path)\""),
                ("\"\(first.path)\"", second.path)
            ] {
                let content = await CopiedFileTextReader().readClipboardText(older + separator + newer + separator)
                XCTAssertEqual(content, .pair(previous: value(first, "old contents"), current: value(second, "new contents")))
            }
        }
    }

    func testRepeatedPathFormsAnIdenticalPair() async throws {
        let file = try write("same.txt", "same contents")
        let content = await CopiedFileTextReader().readClipboardText("\(file.path)\n\(file.path)")
        XCTAssertEqual(content, .pair(previous: value(file, "same contents"), current: value(file, "same contents")))
    }

    func testMalformedAndMixedTextIsPreservedExactly() async throws {
        let file = try write("source.txt", "contents")
        for text in [
            "ordinary text", "", "relative.txt", "~/source.txt", "file://\(file.path)",
            "\"\(file.path)", "\(file.path)\"", "\"\"", "'\(file.path)'",
            "\(file.path)\nnotes", "notes\n\(file.path)", "\(file.path)\n\n\(file.path)",
            "\(file.path)\nrelative.txt", " \(file.path)", "\(file.path)\u{0}"
        ] {
            let content = await CopiedFileTextReader().readClipboardText(text)
            XCTAssertEqual(content, .value(CapturedClipboardValue(text: text)), text)
        }
    }

    func testUnquotedMissingFileOrDirectoryPreservesEntirePayload() async throws {
        let file = try write("source.txt", "contents")
        let missing = directory.appendingPathComponent("missing.txt")
        for text in [missing.path, directory.path, "\(file.path)\n\(missing.path)", "\"\(missing.path)\"\n\(file.path)"] {
            let content = await CopiedFileTextReader().readClipboardText(text)
            XCTAssertEqual(content, .value(CapturedClipboardValue(text: text)))
        }
    }

    func testFullyQuotedPathsUseCopiedFileFallbacks() async throws {
        let missing = directory.appendingPathComponent("missing.txt")
        let empty = try write("empty.txt", "")
        let content = await CopiedFileTextReader().readClipboardText("\"\(missing.path)\"\n\"\(empty.path)\"")
        XCTAssertEqual(content, .pair(
            previous: value(missing, "missing.txt (file not found)"),
            current: value(empty, "empty.txt (empty file)")
        ))
    }

    func testExistingUnquotedEmptyAndOversizedPathsUseFileFallbacks() async throws {
        let empty = try write("empty.txt", "")
        let oversized = try write("oversized.txt", "12345")
        let content = await CopiedFileTextReader(maximumTextFileBytes: 4)
            .readClipboardText("\(empty.path)\n\(oversized.path)")
        XCTAssertEqual(content, .pair(
            previous: value(empty, "empty.txt (empty file)"),
            current: value(oversized, "oversized.txt (file too large)")
        ))
    }

    func testBinaryPathsProduceSingleAndPairFallbacks() async throws {
        let file = try write("source.txt", "contents")
        let binary = directory.appendingPathComponent("binary.txt")
        try Data([0, 1, 2]).write(to: binary)
        let reader = CopiedFileTextReader()
        for text in [binary.path, "\"\(binary.path)\""] {
            let content = await reader.readClipboardText(text)
            XCTAssertEqual(content, .value(value(binary, "binary.txt (binary file)")))
        }
        let forward = await reader.readClipboardText("\(file.path)\n\(binary.path)")
        let reverse = await reader.readClipboardText("\(binary.path)\n\(file.path)")
        XCTAssertEqual(forward, .pair(previous: value(file, "contents"), current: value(binary, "binary.txt (binary file)")))
        XCTAssertEqual(reverse, .pair(previous: value(binary, "binary.txt (binary file)"), current: value(file, "contents")))
    }

    func testMoreThanTwoRecognizedPathsAreIgnored() async throws {
        let files = try ["first", "second", "third"].map { try write($0 + ".txt", $0) }
        for text in [files.map(\.path).joined(separator: "\n"), files.map { "\"\($0.path)\"" }.joined(separator: "\n")] {
            let content = await CopiedFileTextReader().readClipboardText(text)
            XCTAssertEqual(content, .nonText)
        }
        let quotedMissing = (1...3).map { "\"\(directory.path)/missing\($0)\"" }.joined(separator: "\n")
        let content = await CopiedFileTextReader().readClipboardText(quotedMissing)
        XCTAssertEqual(content, .nonText)
    }

    func testUnrecognizedLongListRemainsText() async throws {
        let file = try write("source.txt", "contents")
        let text = "\(file.path)\n\(directory.path)/missing\n\(file.path)"
        let content = await CopiedFileTextReader().readClipboardText(text)
        XCTAssertEqual(content, .value(CapturedClipboardValue(text: text)))
    }

    func testPathPairAtomicallyReplacesHistoryAndRetainsLabels() async throws {
        let old = try write("old.txt", "old contents")
        let new = try write("new.txt", "new contents")
        let history = ClipboardHistory()
        let now = Date()
        history.apply(ClipboardObservation(changeCount: 1, observedAt: now, content: .value(CapturedClipboardValue(text: "earlier capture"))))
        let content = await CopiedFileTextReader().readClipboardText("\"\(old.path)\"\n\"\(new.path)\"")
        XCTAssertEqual(history.apply(ClipboardObservation(changeCount: 2, observedAt: now, content: content)), .accepted)
        XCTAssertEqual(history.previousEntry?.text, "old contents")
        XCTAssertEqual(history.currentEntry?.text, "new contents")
        XCTAssertEqual(history.previousEntry?.sourceFileName, "old.txt")
        XCTAssertEqual(history.currentEntry?.sourceFilePath, new.standardizedFileURL.path)
        XCTAssertEqual(history.entries.count, 2)
    }

    func testTextAndFilePathCanBeCombined() async throws {
        let file = try write("source.txt", "file contents")
        let history = ClipboardHistory()
        for (index, text) in ["copied text", "\"\(file.path)\""].enumerated() {
            let content = await CopiedFileTextReader().readClipboardText(text)
            history.apply(ClipboardObservation(changeCount: index + 1, observedAt: Date(), content: content))
        }
        XCTAssertEqual(history.previousEntry?.text, "copied text")
        XCTAssertEqual(history.currentEntry?.text, "file contents")
    }

    func testBinaryPathPairReplacesCapturesWithTextAndBinaryLabel() async throws {
        let file = try write("source.txt", "contents")
        let binary = directory.appendingPathComponent("binary.zip")
        try Data([0, 1, 2]).write(to: binary)
        let history = ClipboardHistory()
        history.replaceComparisonPair(previous: CapturedClipboardValue(text: "old"), current: CapturedClipboardValue(text: "new"), capturedAt: Date())
        let content = await CopiedFileTextReader().readClipboardText("\(file.path)\n\(binary.path)")
        XCTAssertEqual(history.apply(ClipboardObservation(changeCount: 1, observedAt: Date(), content: content)), .accepted)
        XCTAssertEqual(history.previousEntry?.text, "contents")
        XCTAssertEqual(history.currentEntry?.text, "binary.zip (binary file)")
    }

    func testCancelledReadDoesNotProduceACapture() async throws {
        let file = try write("source.txt", "contents")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CopiedFileTextReader().readClipboardText(file.path)
        }
        let content = await task.value
        XCTAssertEqual(content, .nonText)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func value(_ file: URL, _ text: String) -> CapturedClipboardValue {
        CapturedClipboardValue(text: text, sourceFileName: file.lastPathComponent, sourceFilePath: file.standardizedFileURL.path)
    }
}
