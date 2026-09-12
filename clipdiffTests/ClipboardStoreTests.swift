import Foundation
import XCTest
@testable import ClipDiffCore

final class ClipboardStoreTests: XCTestCase {
    func testConcealedClipboardDoesNotReadTextOrFiles() {
        let pasteboard = FakeClipboardPasteboard(
            typeIdentifiers: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        )

        let snapshot = SystemClipboardStore(pasteboard: pasteboard).readSnapshot()

        XCTAssertEqual(snapshot, .nonText)
        XCTAssertEqual(pasteboard.fileReadCount, 0)
        XCTAssertEqual(pasteboard.stringReadCount, 0)
    }

    func testTransientClipboardDoesNotReadTextOrFiles() {
        let pasteboard = FakeClipboardPasteboard(
            typeIdentifiers: ["public.file-url", "org.nspasteboard.TransientType"]
        )

        let snapshot = SystemClipboardStore(pasteboard: pasteboard).readSnapshot()

        XCTAssertEqual(snapshot, .nonText)
        XCTAssertEqual(pasteboard.fileReadCount, 0)
        XCTAssertEqual(pasteboard.stringReadCount, 0)
    }

    func testOrdinaryClipboardStillReadsFilesBeforeText() {
        let fileURL = URL(fileURLWithPath: "/tmp/example.txt")
        let pasteboard = FakeClipboardPasteboard(
            typeIdentifiers: ["public.file-url", "public.utf8-plain-text"],
            fileURLs: [fileURL],
            string: "/tmp/example.txt"
        )

        let snapshot = SystemClipboardStore(pasteboard: pasteboard).readSnapshot()

        XCTAssertEqual(snapshot, .fileURLs([fileURL]))
        XCTAssertEqual(pasteboard.fileReadCount, 1)
        XCTAssertEqual(pasteboard.stringReadCount, 0)
    }
}

private final class FakeClipboardPasteboard: ClipboardPasteboard {
    let changeCount = 1
    let clipboardTypeIdentifiers: [String]
    private let fileURLs: [URL]
    private let string: String?

    private(set) var fileReadCount = 0
    private(set) var stringReadCount = 0

    init(
        typeIdentifiers: [String],
        fileURLs: [URL] = [],
        string: String? = "secret"
    ) {
        clipboardTypeIdentifiers = typeIdentifiers
        self.fileURLs = fileURLs
        self.string = string
    }

    func readClipboardFileURLs() -> [URL] {
        fileReadCount += 1
        return fileURLs
    }

    func readClipboardString() -> String? {
        stringReadCount += 1
        return string
    }

    func clearClipboardContents() {}
    func writeClipboardString(_ text: String) {}
}
