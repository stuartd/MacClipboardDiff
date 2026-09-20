import Foundation

final class ExternalDiffLauncher {
    private struct ActiveComparison {
        let process: Process
        let directoryURL: URL
    }

    private static let cleanupDelay: TimeInterval = 3

    private let workspace: ExternalDiffWorkspace
    private let lock = NSLock()
    private var activeComparisons: [ObjectIdentifier: ActiveComparison] = [:]

    init(workspace: ExternalDiffWorkspace = ExternalDiffWorkspace()) {
        self.workspace = workspace
        workspace.cleanupStaleComparisons()
    }

    deinit {
        cleanupAll()
    }

    func tryLaunch(
        _ choice: ExternalDiffToolChoice,
        previous: ClipboardEntry,
        current: ClipboardEntry,
        labels: DiffSideLabels
    ) -> Bool {
        let launcherURL = choice.tool.launcherExecutablePath.map(URL.init(fileURLWithPath:))
            ?? choice.executableURL
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            return false
        }

        let files: ExternalDiffFiles
        do {
            files = try workspace.create(
                previousText: previous.text,
                currentText: current.text,
                previousSourceFileName: previous.sourceFileName,
                currentSourceFileName: current.sourceFileName
            )
        } catch {
            return false
        }

        let process = Process()
        process.executableURL = launcherURL
        process.currentDirectoryURL = files.directoryURL
        process.arguments = choice.tool.arguments(
            previousPath: files.previousURL.path,
            currentPath: files.currentURL.path,
            previousLabel: labels.previous,
            currentLabel: labels.current
        )
        if let appURL = Self.reusableMacDiffApplication(for: choice.executableURL) {
            // Launch Services delivers both files to the existing window. Waiting
            // for the app (not just /usr/bin/open) keeps the inputs alive until quit.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-W", "-a", appURL.path, files.previousURL.path, files.currentURL.path]
        }
        process.terminationHandler = { [weak self] process in
            self?.scheduleCleanup(for: process)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            workspace.delete(files.directoryURL)
            return false
        }

        let identifier = ObjectIdentifier(process)
        lock.lock()
        activeComparisons[identifier] = ActiveComparison(
            process: process,
            directoryURL: files.directoryURL
        )
        lock.unlock()

        if !process.isRunning {
            scheduleCleanup(for: process)
        }
        return true
    }

    static func reusableMacDiffApplication(for executableURL: URL) -> URL? {
        let appURL = executableURL.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app",
              let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == "local.macdiff.MacDiff",
              bundle.object(forInfoDictionaryKey: "MacDiffAcceptsComparisonFiles") as? Bool == true,
              bundle.executableURL?.standardizedFileURL == executableURL.resolvingSymlinksInPath().standardizedFileURL else {
            return nil
        }
        return appURL
    }

    func cleanupAll() {
        lock.lock()
        let comparisons = Array(activeComparisons.values)
        activeComparisons.removeAll()
        lock.unlock()

        for comparison in comparisons {
            comparison.process.terminationHandler = nil
            workspace.delete(comparison.directoryURL)
        }
    }

    private func scheduleCleanup(for process: Process) {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.cleanupDelay) { [weak self] in
            self?.cleanup(process)
        }
    }

    private func cleanup(_ process: Process) {
        let identifier = ObjectIdentifier(process)

        lock.lock()
        let comparison = activeComparisons.removeValue(forKey: identifier)
        lock.unlock()

        guard let comparison else { return }
        comparison.process.terminationHandler = nil
        workspace.delete(comparison.directoryURL)
    }
}
