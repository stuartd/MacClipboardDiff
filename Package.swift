// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipDiff",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClipDiffCore", targets: ["ClipDiffCore"])
    ],
    targets: [
        .target(
            name: "ClipDiffCore",
            path: "clipdiff",
            exclude: [
                "AppAbout.swift",
                "Assets.xcassets",
                "clipdiffApp.swift",
                "ClipDiffApplicationDelegate.swift",
                "ClipDiffController.swift",
                "DiagnosticLogWindowController.swift",
                "DiffWindowController.swift",
                "DiffWindowView.swift",
                "ExternalDiffToolDiscovery.swift",
                "ShortcutSettingsWindowController.swift",
                "StatusMenu.swift",
                "UpdateAlerts.swift"
            ],
            sources: [
                "AppVersionFormatter.swift",
                "ClipDiffLog.swift",
                "ClipboardHistory.swift",
                "ClipboardModels.swift",
                "ClipboardObservation.swift",
                "ClipboardStore.swift",
                "CopiedFileTextReader.swift",
                "DiffEngine.swift",
                "InlineDiff.swift",
                "DiffTextFormatting.swift",
                "ExternalDiffLauncher.swift",
                "ExternalDiffSettings.swift",
                "ExternalDiffTool.swift",
                "ExternalDiffWorkspace.swift",
                "FinderComparisonRequest.swift",
                "FinderCaptureIdentity.swift",
                "FinderSingleFileRequestState.swift",
                "GitHubReleaseClient.swift",
                "GlobalShortcut.swift",
                "GlobalShortcutValidator.swift",
                "HotKeyController.swift",
                "LoginItemManager.swift",
                "ReleaseVersion.swift",
                "ShortcutRecorderControl.swift",
                "SingleInstanceLock.swift",
                "UpdateChecker.swift"
            ]
        ),
        .testTarget(
            name: "ClipDiffCoreTests",
            dependencies: ["ClipDiffCore"],
            path: "clipdiffTests"
        )
    ]
)
