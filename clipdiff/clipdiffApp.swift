//
//  clipdiffApp.swift
//  clipdiff
//
//  Created by Stuart on 12/05/2026.
//

import AppKit
import SwiftUI

@main
struct clipdiffApp: App {
    @State private var clipboardMonitor = ClipboardMonitor()
    @State private var diffLauncher = DiffLauncher()

    var body: some Scene {
        MenuBarExtra("clipdiff", systemImage: "doc.on.clipboard") {
            ContentView(clipboardMonitor: clipboardMonitor, diffLauncher: diffLauncher)

            Divider()

            Button("clipdiff") {
                guard let previousText = clipboardMonitor.previousText,
                      let currentText = clipboardMonitor.currentText else {
                    return
                }

                diffLauncher.openDiff(previousText: previousText, currentText: currentText)
            }
            .disabled(!clipboardMonitor.canDiff)

            Divider()

            Button("Choose Diff App...") {
                diffLauncher.chooseDiffApplication()
            }

            Button("Use FileMerge") {
                diffLauncher.resetDiffApplication()
            }
            .disabled(diffLauncher.diffApplicationName == "FileMerge")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }

}
