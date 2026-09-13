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
            [
                "-readonly",
                "-lefttitle=Previous clipboard",
                "-righttitle=Current clipboard",
                previous,
                current
            ]
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

    func testLabelsAndPathsRemainSeparateArguments() throws {
        let fileName = "Read \"me\" — café.md"
        let labels = DiffEngine.makeLabels(
            previous: ClipboardEntry(
                text: "old",
                capturedAt: Date(timeIntervalSince1970: 0),
                sourceFileName: fileName,
                sourceFilePath: "/private/project/old version/\(fileName)"
            ),
            current: ClipboardEntry(
                text: "new",
                capturedAt: Date(timeIntervalSince1970: 1),
                sourceFileName: fileName,
                sourceFilePath: "/private/project/new version/\(fileName)"
            )
        )

        XCTAssertEqual(labels.previous, "Previous clipboard — old version/\(fileName)")
        XCTAssertEqual(labels.current, "Current clipboard — new version/\(fileName)")

        let titleOptions: [(id: String, previous: [String], current: [String])] = [
            ("beyond-compare", ["-lefttitle=\(labels.previous)"], ["-righttitle=\(labels.current)"]),
            ("araxis", ["-title1:\(labels.previous)"], ["-title2:\(labels.current)"]),
            ("kdiff3", ["--L1", labels.previous], ["--L2", labels.current]),
            ("meld", ["--label", labels.previous], ["--label", labels.current]),
            ("diffmerge", ["-t1=\(labels.previous)"], ["-t2=\(labels.current)"])
        ]

        for options in titleOptions {
            let tool = ExternalDiffToolCatalog.tools.first { $0.id == options.id }!
            let arguments = tool.arguments(
                previousPath: previous,
                currentPath: current,
                previousLabel: labels.previous,
                currentLabel: labels.current
            )

            let titles = options.previous + options.current
            let titleIndex = try XCTUnwrap(arguments.firstIndex(of: titles[0]), options.id)
            XCTAssertEqual(Array(arguments.dropFirst(titleIndex).prefix(titles.count)), titles, options.id)
            XCTAssertEqual(Array(arguments.suffix(2)), [previous, current], options.id)
            XCTAssertFalse(arguments.contains { $0.contains("/private/project/") }, options.id)
        }
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
