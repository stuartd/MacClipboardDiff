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
