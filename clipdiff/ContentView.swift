//
//  ContentView.swift
//  clipdiff
//
//  Created by Stuart on 12/05/2026.
//

import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardMonitor {
    private(set) var currentText: String?
    private(set) var previousText: String?

    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?

    init() {
        start()
    }

    var canDiff: Bool {
        previousText != nil && currentText != nil
    }

    var statusText: String {
        switch (previousText, currentText) {
        case (.some, .some):
            "Ready to diff"
        case (nil, .some):
            "Copy another text value"
        default:
            "Waiting for copied text"
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.readPasteboardIfNeeded()
            }
        }
    }

    private func readPasteboardIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        guard pasteboard.availableType(from: [.string]) != nil,
              let copiedText = pasteboard.string(forType: .string) else {
            clearText()
            return
        }

        if let currentText {
            previousText = currentText
        }
        currentText = copiedText
    }

    private func clearText() {
        previousText = nil
        currentText = nil
    }
}

@MainActor
@Observable
final class DiffLauncher {
    private var diffApplicationPath: String
    private(set) var lastError: String?

    @ObservationIgnored private let diffApplicationPathKey = "diffApplicationPath"

    init() {
        diffApplicationPath = UserDefaults.standard.string(forKey: diffApplicationPathKey) ?? ""
    }

    var diffApplicationName: String {
        guard !diffApplicationPath.isEmpty else { return "FileMerge" }
        return URL(fileURLWithPath: diffApplicationPath).deletingPathExtension().lastPathComponent
    }

    func chooseDiffApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the app to open clipdiff comparisons."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        diffApplicationPath = url.path
        UserDefaults.standard.set(diffApplicationPath, forKey: diffApplicationPathKey)
        lastError = nil
    }

    func resetDiffApplication() {
        diffApplicationPath = ""
        UserDefaults.standard.removeObject(forKey: diffApplicationPathKey)
        lastError = nil
    }

    func openDiff(previousText: String, currentText: String) {
        do {
            let filePair = try writeTemporaryFiles(previousText: previousText, currentText: currentText)

            if diffApplicationPath.isEmpty {
                try runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/opendiff"), arguments: [filePair.previous.path, filePair.current.path])
            } else {
                try runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", diffApplicationPath, filePair.previous.path, filePair.current.path])
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func writeTemporaryFiles(previousText: String, currentText: String) throws -> (previous: URL, current: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipdiff")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let previousURL = directory.appendingPathComponent("previous.txt")
        let currentURL = directory.appendingPathComponent("current.txt")

        try previousText.write(to: previousURL, atomically: true, encoding: .utf8)
        try currentText.write(to: currentURL, atomically: true, encoding: .utf8)

        return (previousURL, currentURL)
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }
}

struct ContentView: View {
    let clipboardMonitor: ClipboardMonitor
    let diffLauncher: DiffLauncher

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(clipboardMonitor.statusText)
                .font(.headline)

            Text("Diff app: \(diffLauncher.diffApplicationName)")
                .foregroundStyle(.secondary)

            if let lastError = diffLauncher.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding()
    }
}

#Preview {
    ContentView(clipboardMonitor: ClipboardMonitor(), diffLauncher: DiffLauncher())
}
