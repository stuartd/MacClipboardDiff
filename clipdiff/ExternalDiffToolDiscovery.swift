import AppKit
import Foundation

enum ExternalDiffToolDiscovery {
    static func findInstalled(selectedExecutablePath: String?) -> [ExternalDiffToolChoice] {
        var choices: [ExternalDiffToolChoice] = []
        var seenPaths = Set<String>()

        for tool in ExternalDiffToolCatalog.tools {
            guard let executableURL = findExecutable(for: tool) else { continue }
            append(
                ExternalDiffToolChoice(tool: tool, executableURL: executableURL),
                to: &choices,
                seenPaths: &seenPaths
            )
        }

        if let selectedExecutablePath,
           FileManager.default.isExecutableFile(atPath: selectedExecutablePath) {
            let executableURL = URL(fileURLWithPath: selectedExecutablePath)
            append(
                ExternalDiffToolChoice(
                    tool: ExternalDiffToolCatalog.matchExecutable(at: executableURL),
                    executableURL: executableURL
                ),
                to: &choices,
                seenPaths: &seenPaths
            )
        }

        return choices
    }

    static func choice(forSelectedURL selectedURL: URL) -> ExternalDiffToolChoice? {
        let selectedExecutableURL: URL
        let selectedTool: ExternalDiffTool

        if selectedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            guard let matchedTool = matchedTool(forApplicationURL: selectedURL),
                  let resolvedURL = resolveExecutableURL(in: selectedURL, for: matchedTool) else {
                guard let bundleExecutableURL = Bundle(url: selectedURL)?.executableURL else {
                    return nil
                }
                selectedExecutableURL = bundleExecutableURL
                selectedTool = ExternalDiffToolCatalog.matchExecutable(at: bundleExecutableURL)
                return validatedChoice(
                    tool: selectedTool,
                    executableURL: selectedExecutableURL
                )
            }
            selectedTool = matchedTool
            selectedExecutableURL = resolvedURL
        } else {
            selectedExecutableURL = selectedURL
            selectedTool = ExternalDiffToolCatalog.matchExecutable(at: selectedExecutableURL)
        }

        return validatedChoice(tool: selectedTool, executableURL: selectedExecutableURL)
    }

    private static func findExecutable(for tool: ExternalDiffTool) -> URL? {
        for bundleIdentifier in tool.bundleIdentifiers {
            if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ), let executableURL = resolveExecutableURL(in: applicationURL, for: tool) {
                return executableURL
            }
        }

        for applicationURL in knownApplicationURLs(for: tool) {
            if let executableURL = resolveExecutableURL(in: applicationURL, for: tool) {
                return executableURL
            }
        }

        for path in tool.knownExecutablePaths {
            let candidate = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: path),
               matches(candidate, tool: tool) {
                return candidate
            }
        }

        return findOnPath(tool.executableNames, tool: tool)
    }

    private static func knownApplicationURLs(for tool: ExternalDiffTool) -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
        return roots.flatMap { root in
            tool.applicationNames.map { root.appendingPathComponent($0, isDirectory: true) }
        }
    }

    private static func resolveExecutableURL(
        in applicationURL: URL,
        for tool: ExternalDiffTool
    ) -> URL? {
        for relativePath in tool.bundledExecutablePaths {
            let candidate = applicationURL.appendingPathComponent(relativePath)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        guard let bundleExecutableURL = Bundle(url: applicationURL)?.executableURL,
              tool.executableNames.contains(where: {
                  $0.caseInsensitiveCompare(bundleExecutableURL.lastPathComponent) == .orderedSame
              }) else {
            return nil
        }
        return bundleExecutableURL
    }

    private static func matchedTool(forApplicationURL applicationURL: URL) -> ExternalDiffTool? {
        let applicationName = applicationURL.lastPathComponent
        if let match = ExternalDiffToolCatalog.tools.first(where: { tool in
            tool.applicationNames.contains(where: {
                $0.caseInsensitiveCompare(applicationName) == .orderedSame
            })
        }) {
            return match
        }

        guard let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier else {
            return nil
        }
        return ExternalDiffToolCatalog.tools.first { tool in
            tool.bundleIdentifiers.contains(where: {
                $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            })
        }
    }

    private static func findOnPath(
        _ executableNames: [String],
        tool: ExternalDiffTool
    ) -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }

        for directory in path.split(separator: ":") {
            for executableName in executableNames {
                let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent(executableName)
                if FileManager.default.isExecutableFile(atPath: candidate.path),
                   matches(candidate, tool: tool) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func matches(_ executableURL: URL, tool: ExternalDiffTool) -> Bool {
        ExternalDiffToolCatalog.matchExecutable(
            at: executableURL.resolvingSymlinksInPath()
        ).id == tool.id
    }

    private static func validatedChoice(
        tool: ExternalDiffTool,
        executableURL: URL
    ) -> ExternalDiffToolChoice? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }
        return ExternalDiffToolChoice(tool: tool, executableURL: executableURL)
    }

    private static func append(
        _ choice: ExternalDiffToolChoice,
        to choices: inout [ExternalDiffToolChoice],
        seenPaths: inout Set<String>
    ) {
        let path = choice.executableURL.standardizedFileURL.path
        guard seenPaths.insert(path).inserted else { return }
        choices.append(choice)
    }
}
