import XCTest
@testable import ClipDiffCore

final class ExternalDiffToolCatalogTests: XCTestCase {
    private let previous = "/tmp/ClipDiff Test/Previous clipboard.txt"
    private let current = "/tmp/ClipDiff Test/Current clipboard.txt"

    func testCatalogSupportsCommonMacDiffApplications() {
        XCTAssertEqual(
            ExternalDiffToolCatalog.tools.map(\.id),
            [
                "filemerge", "kaleidoscope", "beyond-compare", "araxis", "vscode",
                "cursor", "bbedit", "kdiff3", "meld", "p4merge", "diffmerge"
            ]
        )
    }

    func testWaitCapableToolsKeepTemporaryFilesAlive() {
        XCTAssertEqual(
            arguments("kaleidoscope"),
            ["--wait", "--no-stdin", previous, current]
        )
        XCTAssertEqual(
            arguments("vscode"),
            ["--diff", "--wait", previous, current]
        )
        XCTAssertEqual(
            arguments("cursor"),
            ["--diff", "--wait", previous, current]
        )
        XCTAssertEqual(
            arguments("bbedit"),
            ["--wait", previous, current]
        )
    }

    func testFileMergeUsesOpenDiffLauncher() {
        let tool = ExternalDiffToolCatalog.tools.first { $0.id == "filemerge" }!

        XCTAssertEqual(tool.launcherExecutablePath, "/usr/bin/opendiff")
        XCTAssertEqual(
            tool.arguments(previousPath: previous, currentPath: current),
            [previous, current]
        )
    }

    func testKnownToolsReceiveReadOnlyAndSideTitleArguments() {
        XCTAssertEqual(
            arguments("beyond-compare"),
            ["-readonly", previous, current]
        )
        XCTAssertEqual(
            arguments("araxis"),
            [
                "-wait", "-readonly", "-2",
                "-title1:Previous clipboard",
                "-title2:Current clipboard",
                previous,
                current
            ]
        )
        XCTAssertEqual(
            arguments("kdiff3"),
            [
                "--L1", "Previous clipboard",
                "--L2", "Current clipboard",
                previous,
                current
            ]
        )
    }

    func testLabelsAndPathsRemainSeparateArguments() {
        let tool = ExternalDiffToolCatalog.tools.first { $0.id == "araxis" }!

        XCTAssertEqual(
            tool.arguments(
                previousPath: previous,
                currentPath: current,
                previousLabel: "Previous clipboard — old file.swift",
                currentLabel: "Current clipboard — new file.swift"
            ),
            [
                "-wait", "-readonly", "-2",
                "-title1:Previous clipboard — old file.swift",
                "-title2:Current clipboard — new file.swift",
                previous,
                current
            ]
        )
    }

    func testUnknownExecutableUsesPositionalPaths() {
        let tool = ExternalDiffToolCatalog.matchExecutable(
            at: URL(fileURLWithPath: "/Applications/My Diff.app/Contents/MacOS/My Diff")
        )

        XCTAssertEqual(tool.id, "custom")
        XCTAssertEqual(
            tool.arguments(previousPath: previous, currentPath: current),
            [previous, current]
        )
    }

    func testGenericCompareExecutableIsNotMistakenForAraxis() {
        XCTAssertEqual(
            ExternalDiffToolCatalog.matchExecutable(
                at: URL(fileURLWithPath: "/usr/local/bin/compare")
            ).id,
            "custom"
        )
        XCTAssertEqual(
            ExternalDiffToolCatalog.matchExecutable(
                at: URL(fileURLWithPath: "/Applications/Araxis Merge.app/Contents/Utilities/compare")
            ).id,
            "araxis"
        )
    }

    private func arguments(_ id: String) -> [String] {
        ExternalDiffToolCatalog.tools.first { $0.id == id }!.arguments(
            previousPath: previous,
            currentPath: current
        )
    }
}
