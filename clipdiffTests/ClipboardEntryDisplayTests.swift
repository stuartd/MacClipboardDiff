import XCTest
@testable import ClipDiffCore

final class ClipboardEntryDisplayTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testDifferentFileNamesNeedNoPathContext() {
        let labels = ClipboardEntryDisplay.resolveFileLabels(
            previous: entry("before.swift", path: "/repo/Sources/before.swift"),
            current: entry("after.swift", path: "/repo/Sources/after.swift")
        )

        XCTAssertEqual(labels, ClipboardFileLabels(previous: "before.swift", current: "after.swift"))
    }

    func testMatchingFileNamesUseShortestUniquePathSuffix() {
        let labels = ClipboardEntryDisplay.resolveFileLabels(
            previous: entry(
                "settings.json",
                path: "/worktrees/branch-a/project/Sources/settings.json"
            ),
            current: entry(
                "settings.json",
                path: "/worktrees/branch-b/project/Sources/settings.json"
            )
        )

        XCTAssertEqual(labels.previous, "branch-a/project/Sources/settings.json")
        XCTAssertEqual(labels.current, "branch-b/project/Sources/settings.json")
    }

    func testMatchingFileNamesInDifferentImmediateParentsUseOnlyThoseParents() {
        let labels = ClipboardEntryDisplay.resolveFileLabels(
            previous: entry("app.swift", path: "/repo/old/app.swift"),
            current: entry("app.swift", path: "/repo/new/app.swift")
        )

        XCTAssertEqual(labels.previous, "old/app.swift")
        XCTAssertEqual(labels.current, "new/app.swift")
    }

    func testSameFilePathDoesNotAddRedundantContext() {
        let labels = ClipboardEntryDisplay.resolveFileLabels(
            previous: entry("app.swift", path: "/repo/app.swift"),
            current: entry("app.swift", path: "/repo/app.swift")
        )

        XCTAssertEqual(labels, ClipboardFileLabels(previous: "app.swift", current: "app.swift"))
    }

    private func entry(_ fileName: String, path: String) -> ClipboardEntry {
        ClipboardEntry(
            text: "contents",
            capturedAt: capturedAt,
            sourceFileName: fileName,
            sourceFilePath: path
        )
    }
}
