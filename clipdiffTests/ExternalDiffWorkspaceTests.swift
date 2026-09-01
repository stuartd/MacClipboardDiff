import Foundation
import XCTest
@testable import ClipDiffCore

final class ExternalDiffWorkspaceTests: XCTestCase {
    func testCreatesExactReadOnlyUTF8TextInUniqueComparisonDirectories() throws {
        let root = temporaryDirectory()
        defer { ExternalDiffWorkspace.tryDelete(root) }
        let workspace = ExternalDiffWorkspace(rootDirectoryURL: root)

        let first = try workspace.create(
            previousText: "previous\r\n秘密\t",
            currentText: "current\n😀"
        )
        let second = try workspace.create(previousText: "one", currentText: "two")

        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        XCTAssertEqual(first.previousURL.lastPathComponent, "Previous clipboard.txt")
        XCTAssertEqual(first.currentURL.lastPathComponent, "Current clipboard.txt")
        XCTAssertEqual(try String(contentsOf: first.previousURL, encoding: .utf8), "previous\r\n秘密\t")
        XCTAssertEqual(try String(contentsOf: first.currentURL, encoding: .utf8), "current\n😀")
        XCTAssertEqual(permissions(first.previousURL), 0o400)
        XCTAssertEqual(permissions(first.currentURL), 0o400)
    }

    func testFileBackedValuesKeepSafeBasenamesOnSeparateSides() throws {
        let root = temporaryDirectory()
        defer { ExternalDiffWorkspace.tryDelete(root) }
        let workspace = ExternalDiffWorkspace(rootDirectoryURL: root)

        let files = try workspace.create(
            previousText: "old",
            currentText: "new",
            previousSourceFileName: "same:name.swift",
            currentSourceFileName: "same:name.swift"
        )

        XCTAssertEqual(files.previousURL.lastPathComponent, "same_name.swift")
        XCTAssertEqual(files.currentURL.lastPathComponent, "same_name.swift")
        XCTAssertEqual(files.previousURL.deletingLastPathComponent().lastPathComponent, "Previous")
        XCTAssertEqual(files.currentURL.deletingLastPathComponent().lastPathComponent, "Current")
    }

    func testStaleCleanupRemovesComparisonDirectories() throws {
        let root = temporaryDirectory()
        defer { ExternalDiffWorkspace.tryDelete(root) }
        let workspace = ExternalDiffWorkspace(rootDirectoryURL: root)
        let files = try workspace.create(previousText: "secret one", currentText: "secret two")

        workspace.cleanupStaleComparisons()

        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try! FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as! NSNumber).intValue
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDiffTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
