import XCTest
@testable import ClipDiffCore

final class CopiedFileTextReaderTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDiff.CopiedFileTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
    }

    func testUTF8TextFileReturnsContentsAndMetadata() throws {
        let url = try write("source file.txt", text: "first\nsecond")

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, "first\nsecond")
        XCTAssertEqual(result?.fileName, "source file.txt")
        XCTAssertEqual(result?.filePath, url.standardizedFileURL.path)
    }

    func testUTF16TextIsDecodedWithoutByteOrderMark() throws {
        let contents = "echo snowman ☃"
        var data = Data([0xFF, 0xFE])
        data.append(contents.data(using: .utf16LittleEndian)!)
        let url = try write("unicode.command", data: data)

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, contents)
    }

    func testByteOrderMarklessUTF16IsDetected() throws {
        let contents = "alpha bravo charlie"
        let data = contents.data(using: .utf16LittleEndian)!
        let url = try write("unicode.txt", data: data)

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, contents)
    }

    func testWindows1252TextIsDecoded() throws {
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        let url = try write("legacy.txt", data: data)

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, "café")
    }

    func testBinaryContentUsesFilenameFallbackEvenWithTextExtension() throws {
        let url = try write("misleading.txt", data: Data([0x01, 0x00, 0x02, 0x7F]))

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, "misleading.txt (binary file)")
    }

    func testKnownBinaryExtensionIsNeverDecodedAsText() throws {
        let url = try write("library.dylib", text: "looks harmless")

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, "library.dylib (binary file)")
    }

    func testByteOrderMarkOnlyFileUsesEmptyFallback() throws {
        let url = try write("empty-utf8.txt", data: Data([0xEF, 0xBB, 0xBF]))

        let result = CopiedFileTextReader().readFile(at: url)

        XCTAssertEqual(result?.text, "empty-utf8.txt (empty file)")
    }

    func testEmptyMissingDirectoryAndOversizedFallbackReasons() throws {
        let empty = try write("empty.txt", data: Data())
        let missing = testDirectory.appendingPathComponent("missing.txt")
        let folder = testDirectory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let oversized = try write("large.txt", text: "five!")
        let reader = CopiedFileTextReader(maximumTextFileBytes: 4)

        XCTAssertEqual(reader.readFile(at: empty)?.text, "empty.txt (empty file)")
        XCTAssertEqual(reader.readFile(at: missing)?.text, "missing.txt (file not found)")
        XCTAssertEqual(reader.readFile(at: folder)?.text, "folder (directory)")
        XCTAssertEqual(reader.readFile(at: oversized)?.text, "large.txt (file too large)")
    }

    func testTwoFilesReturnComparisonValuesInClipboardOrder() async throws {
        let first = try write("first.txt", text: "first contents")
        let second = try write("second.txt", text: "second contents")

        let values = await CopiedFileTextReader().readValues(from: [first, second])

        XCTAssertEqual(values.map(\.text), ["first contents", "second contents"])
        XCTAssertEqual(values.map(\.fileName), ["first.txt", "second.txt"])
    }

    func testMoreThanTwoFilesAreIgnoredWithoutReading() async throws {
        let first = try write("first.txt", text: "first")
        let second = try write("second.txt", text: "second")
        let third = try write("third.txt", text: "third")

        let values = await CopiedFileTextReader().readValues(from: [first, second, third])

        XCTAssertTrue(values.isEmpty)
    }

    private func write(_ name: String, text: String) throws -> URL {
        try write(name, data: Data(text.utf8))
    }

    private func write(_ name: String, data: Data) throws -> URL {
        let url = testDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
