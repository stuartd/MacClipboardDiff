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
                "Assets.xcassets",
                "clipdiffApp.swift",
                "ClipDiffController.swift",
                "DiffWindowController.swift",
                "DiffWindowView.swift",
                "HotKeyController.swift",
                "MenuContentView.swift"
            ],
            sources: [
                "ClipboardHistory.swift",
                "ClipboardModels.swift",
                "ClipboardTextStore.swift",
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
