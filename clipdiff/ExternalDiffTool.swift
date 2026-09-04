import Foundation

struct ExternalDiffTool {
    typealias ArgumentBuilder = (
        _ previousPath: String,
        _ currentPath: String,
        _ previousLabel: String,
        _ currentLabel: String
    ) -> [String]

    let id: String
    let displayName: String
    let executableNames: [String]
    let applicationNames: [String]
    let bundleIdentifiers: [String]
    let bundledExecutablePaths: [String]
    let knownExecutablePaths: [String]
    let launcherExecutablePath: String?
    private let argumentBuilder: ArgumentBuilder

    init(
        id: String,
        displayName: String,
        executableNames: [String],
        applicationNames: [String] = [],
        bundleIdentifiers: [String] = [],
        bundledExecutablePaths: [String] = [],
        knownExecutablePaths: [String] = [],
        launcherExecutablePath: String? = nil,
        argumentBuilder: @escaping ArgumentBuilder
    ) {
        self.id = id
        self.displayName = displayName
        self.executableNames = executableNames
        self.applicationNames = applicationNames
        self.bundleIdentifiers = bundleIdentifiers
        self.bundledExecutablePaths = bundledExecutablePaths
        self.knownExecutablePaths = knownExecutablePaths
        self.launcherExecutablePath = launcherExecutablePath
        self.argumentBuilder = argumentBuilder
    }

    func arguments(
        previousPath: String,
        currentPath: String,
        previousLabel: String = "Previous clipboard",
        currentLabel: String = "Current clipboard"
    ) -> [String] {
        argumentBuilder(previousPath, currentPath, previousLabel, currentLabel)
    }
}

struct ExternalDiffToolChoice: Identifiable {
    let tool: ExternalDiffTool
    let executableURL: URL

    var id: String {
        executableURL.standardizedFileURL.path
    }

    var displayName: String {
        tool.displayName
    }
}

enum ExternalDiffToolCatalog {
    static let tools: [ExternalDiffTool] = [
        ExternalDiffTool(
            id: "filemerge",
            displayName: "FileMerge",
            executableNames: ["FileMerge", "opendiff"],
            applicationNames: ["FileMerge.app"],
            bundleIdentifiers: ["com.apple.FileMerge"],
            bundledExecutablePaths: ["Contents/MacOS/FileMerge"],
            knownExecutablePaths: [
                "/Applications/Xcode.app/Contents/Applications/FileMerge.app/Contents/MacOS/FileMerge"
            ],
            launcherExecutablePath: "/usr/bin/opendiff",
            argumentBuilder: positionalArguments
        ),
        ExternalDiffTool(
            id: "kaleidoscope",
            displayName: "Kaleidoscope",
            executableNames: ["ksdiff"],
            applicationNames: ["Kaleidoscope.app"],
            bundleIdentifiers: ["com.blackpixel.kaleidoscope", "com.kaleidoscopeapp.Kaleidoscope"],
            bundledExecutablePaths: ["Contents/MacOS/ksdiff"],
            knownExecutablePaths: standardCommandPaths("ksdiff"),
            argumentBuilder: { previous, current, _, _ in
                ["--wait", "--no-stdin", previous, current]
            }
        ),
        ExternalDiffTool(
            id: "beyond-compare",
            displayName: "Beyond Compare",
            executableNames: ["bcomp", "bcompare"],
            applicationNames: ["Beyond Compare.app"],
            bundleIdentifiers: ["com.ScooterSoftware.BeyondCompare", "com.scootersoftware.BeyondCompare"],
            bundledExecutablePaths: ["Contents/MacOS/bcomp"],
            knownExecutablePaths: standardCommandPaths("bcomp") + standardCommandPaths("bcompare"),
            argumentBuilder: { previous, current, _, _ in
                ["-readonly", previous, current]
            }
        ),
        ExternalDiffTool(
            id: "araxis",
            displayName: "Araxis Merge",
            executableNames: ["compare"],
            applicationNames: ["Araxis Merge.app", "Merge.app"],
            bundleIdentifiers: ["com.araxis.merge"],
            bundledExecutablePaths: [
                "Contents/Utilities/compare",
                "Contents/MacOS/compare"
            ],
            knownExecutablePaths: standardCommandPaths("compare"),
            argumentBuilder: { previous, current, previousLabel, currentLabel in
                [
                    "-wait", "-readonly", "-2",
                    "-title1:\(previousLabel)",
                    "-title2:\(currentLabel)",
                    previous,
                    current
                ]
            }
        ),
        codeTool(
            id: "vscode",
            displayName: "Visual Studio Code",
            executableName: "code",
            applicationNames: ["Visual Studio Code.app", "Visual Studio Code - Insiders.app"],
            bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
            bundledExecutablePaths: ["Contents/Resources/app/bin/code"]
        ),
        codeTool(
            id: "cursor",
            displayName: "Cursor",
            executableName: "cursor",
            applicationNames: ["Cursor.app"],
            bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            bundledExecutablePaths: ["Contents/Resources/app/bin/cursor"]
        ),
        ExternalDiffTool(
            id: "bbedit",
            displayName: "BBEdit",
            executableNames: ["bbdiff"],
            applicationNames: ["BBEdit.app"],
            bundleIdentifiers: ["com.barebones.bbedit"],
            bundledExecutablePaths: ["Contents/Helpers/bbdiff", "Contents/MacOS/bbdiff"],
            knownExecutablePaths: standardCommandPaths("bbdiff"),
            argumentBuilder: { previous, current, _, _ in
                ["--wait", previous, current]
            }
        ),
        ExternalDiffTool(
            id: "kdiff3",
            displayName: "KDiff3",
            executableNames: ["kdiff3"],
            applicationNames: ["KDiff3.app", "kdiff3.app"],
            bundleIdentifiers: ["org.kde.kdiff3"],
            bundledExecutablePaths: ["Contents/MacOS/kdiff3"],
            knownExecutablePaths: standardCommandPaths("kdiff3"),
            argumentBuilder: { previous, current, previousLabel, currentLabel in
                [
                    "--L1", previousLabel,
                    "--L2", currentLabel,
                    previous,
                    current
                ]
            }
        ),
        ExternalDiffTool(
            id: "meld",
            displayName: "Meld",
            executableNames: ["meld"],
            applicationNames: ["Meld.app", "meld.app"],
            bundleIdentifiers: ["org.gnome.meld"],
            bundledExecutablePaths: ["Contents/MacOS/meld"],
            knownExecutablePaths: standardCommandPaths("meld"),
            argumentBuilder: positionalArguments
        ),
        ExternalDiffTool(
            id: "p4merge",
            displayName: "P4Merge",
            executableNames: ["p4merge", "launchp4merge"],
            applicationNames: ["p4merge.app", "P4Merge.app"],
            bundleIdentifiers: ["com.perforce.p4merge"],
            bundledExecutablePaths: [
                "Contents/Resources/launchp4merge",
                "Contents/MacOS/p4merge"
            ],
            knownExecutablePaths: standardCommandPaths("p4merge"),
            argumentBuilder: positionalArguments
        ),
        ExternalDiffTool(
            id: "diffmerge",
            displayName: "SourceGear DiffMerge",
            executableNames: ["sgdm", "DiffMerge"],
            applicationNames: ["DiffMerge.app"],
            bundleIdentifiers: ["com.sourcegear.DiffMerge"],
            bundledExecutablePaths: ["Contents/MacOS/DiffMerge", "Contents/MacOS/sgdm"],
            knownExecutablePaths: standardCommandPaths("sgdm"),
            argumentBuilder: { previous, current, previousLabel, currentLabel in
                [
                    "-caption=ClipDiff",
                    "-t1=\(previousLabel)",
                    "-t2=\(currentLabel)",
                    "-ro2",
                    previous,
                    current
                ]
            }
        )
    ]

    static func matchExecutable(at executableURL: URL) -> ExternalDiffTool {
        let executableName = executableURL.lastPathComponent
        let path = executableURL.resolvingSymlinksInPath().standardizedFileURL.path

        for tool in tools where tool.executableNames.contains(where: {
            $0.caseInsensitiveCompare(executableName) == .orderedSame
        }) {
            if tool.id == "araxis" &&
                executableName.caseInsensitiveCompare("compare") == .orderedSame &&
                !path.localizedCaseInsensitiveContains("araxis") {
                continue
            }

            return tool
        }

        let name = executableURL.deletingPathExtension().lastPathComponent
        return ExternalDiffTool(
            id: "custom",
            displayName: "Custom (\(name))",
            executableNames: [executableName],
            argumentBuilder: positionalArguments
        )
    }

    private static func codeTool(
        id: String,
        displayName: String,
        executableName: String,
        applicationNames: [String],
        bundleIdentifiers: [String],
        bundledExecutablePaths: [String]
    ) -> ExternalDiffTool {
        ExternalDiffTool(
            id: id,
            displayName: displayName,
            executableNames: [executableName],
            applicationNames: applicationNames,
            bundleIdentifiers: bundleIdentifiers,
            bundledExecutablePaths: bundledExecutablePaths,
            knownExecutablePaths: standardCommandPaths(executableName),
            argumentBuilder: { previous, current, _, _ in
                ["--diff", "--wait", previous, current]
            }
        )
    }

    private static func standardCommandPaths(_ command: String) -> [String] {
        [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)"
        ]
    }

    nonisolated private static func positionalArguments(
        previous: String,
        current: String,
        previousLabel: String,
        currentLabel: String
    ) -> [String] {
        [previous, current]
    }
}
