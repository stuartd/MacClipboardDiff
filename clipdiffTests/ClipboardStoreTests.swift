import Foundation
import XCTest
#if canImport(AppKit)
import AppKit
#endif
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

    func testCopyDiffPublishesTextAndBothPrivacyMarkersTogether() {
        let pasteboard = FakeClipboardPasteboard(typeIdentifiers: ["public.utf8-plain-text"])
        let store = SystemClipboardStore(pasteboard: pasteboard)
        let text = "--- Previous\n+++ Current\n- old\n+ café ☃\tnew"
        let before = store.changeCount

        store.replaceText(text)

        XCTAssertEqual(pasteboard.replacementCount, 1)
        XCTAssertEqual(pasteboard.writtenText, text)
        XCTAssertEqual(Set(pasteboard.writtenPrivacyTypes), Set([
            "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"
        ]))
        XCTAssertEqual(pasteboard.writtenPrivacyTypes.count, 2)
        XCTAssertGreaterThan(store.changeCount, before)
    }

    func testExportedDiffIsExcludedBeforeReadingBackAnyPayload() {
        let pasteboard = FakeClipboardPasteboard(typeIdentifiers: [])
        let store = SystemClipboardStore(pasteboard: pasteboard)
        store.replaceText("copied diff")

        XCTAssertEqual(store.readSnapshot(), .nonText)
        XCTAssertEqual(pasteboard.fileReadCount, 0)
        XCTAssertEqual(pasteboard.stringReadCount, 0)
    }

    func testCopyDiffReplacesOldFilePayloadWhileKeepingTextPasteable() {
        let pasteboard = FakeClipboardPasteboard(
            typeIdentifiers: ["public.file-url"], fileURLs: [URL(fileURLWithPath: "/tmp/old.txt")]
        )
        let text = "--- previous\n+++ current\n- old\n+ new"
        SystemClipboardStore(pasteboard: pasteboard).replaceText(text)

        XCTAssertEqual(pasteboard.readClipboardString(), text)
        XCTAssertTrue(pasteboard.readClipboardFileURLs().isEmpty)
        XCTAssertFalse(pasteboard.clipboardTypeIdentifiers.contains("public.file-url"))
    }

    #if canImport(AppKit)
    func testPrivateMacPasteboardPublishesOneItemWithStringAndPrivacyMarkers() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = SystemClipboardStore(pasteboard: pasteboard)
        let text = "--- previous\n+++ current\n- café\n+ 日本語\t☃"
        let before = pasteboard.changeCount

        store.replaceText(text)

        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.string(forType: .string), text)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        for identifier in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
            let type = NSPasteboard.PasteboardType(identifier)
            XCTAssertTrue(item.types.contains(type))
            XCTAssertNotNil(item.data(forType: type))
        }
        XCTAssertGreaterThan(pasteboard.changeCount, before)
        XCTAssertEqual(store.readSnapshot(), .nonText)
    }
    #endif

}

private final class FakeClipboardPasteboard: ClipboardPasteboard {
    private(set) var changeCount = 1
    private(set) var clipboardTypeIdentifiers: [String]
    private var fileURLs: [URL]
    private var string: String?
    private(set) var writtenText: String?
    private(set) var writtenPrivacyTypes: [String] = []
    private(set) var replacementCount = 0

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

    func replaceClipboardString(_ text: String, privacyTypeIdentifiers: [String]) {
        replacementCount += 1
        writtenText = text
        writtenPrivacyTypes = privacyTypeIdentifiers
        string = text
        fileURLs = []
        clipboardTypeIdentifiers = ["public.utf8-plain-text"] + privacyTypeIdentifiers
        changeCount += 1
    }
}
