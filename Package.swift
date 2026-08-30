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
                "ClipDiffController.swift",
                "ClipboardStore.swift",
                "DiffWindowController.swift",
                "DiffWindowView.swift",
                "HotKeyController.swift",
                "MenuContentView.swift"
            ],
            sources: [
                "AppVersionFormatter.swift",
                "ClipboardHistory.swift",
                "ClipboardModels.swift",
                "ClipboardObservation.swift",
                "CopiedFileTextReader.swift",
                "DiffEngine.swift"
            ]
        ),
        .testTarget(
            name: "ClipDiffCoreTests",
            dependencies: ["ClipDiffCore"],
            path: "clipdiffTests"
        )
    ]
)
