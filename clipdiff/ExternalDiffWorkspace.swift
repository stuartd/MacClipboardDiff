import Foundation

struct ExternalDiffFiles {
    let directoryURL: URL
    let previousURL: URL
    let currentURL: URL
}

final class ExternalDiffWorkspace {
    private let rootDirectoryURL: URL
    private let fileManager: FileManager

    init(
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("ClipDiff", isDirectory: true)
            .appendingPathComponent("External Comparisons", isDirectory: true)
        self.fileManager = fileManager
    }

    func create(
        previousText: String,
        currentText: String,
        previousSourceFileName: String? = nil,
        currentSourceFileName: String? = nil
    ) throws -> ExternalDiffFiles {
        try fileManager.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let directoryURL = rootDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let previousURL = try sideURL(
                comparisonDirectoryURL: directoryURL,
                side: "Previous",
                defaultFileName: "Previous clipboard.txt",
                sourceFileName: previousSourceFileName
            )
            let currentURL = try sideURL(
                comparisonDirectoryURL: directoryURL,
                side: "Current",
                defaultFileName: "Current clipboard.txt",
                sourceFileName: currentSourceFileName
            )

            try writeReadOnly(previousText, to: previousURL)
            try writeReadOnly(currentText, to: currentURL)

            return ExternalDiffFiles(
                directoryURL: directoryURL,
                previousURL: previousURL,
                currentURL: currentURL
            )
        } catch {
            _ = Self.tryDelete(directoryURL, fileManager: fileManager)
            throw error
        }
    }

    func cleanupStaleComparisons() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for directoryURL in directories {
            let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            _ = Self.tryDelete(directoryURL, fileManager: fileManager)
        }
    }

    @discardableResult
    func delete(_ directoryURL: URL) -> Bool {
        Self.tryDelete(directoryURL, fileManager: fileManager)
    }

    @discardableResult
    static func tryDelete(
        _ directoryURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return true }

        if let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) {
            for case let fileURL as URL in enumerator {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(
                    atPath: fileURL.path,
                    isDirectory: &isDirectory
                )
                try? fileManager.setAttributes(
                    [.posixPermissions: isDirectory.boolValue ? 0o700 : 0o600],
                    ofItemAtPath: fileURL.path
                )
            }
        }

        do {
            try fileManager.removeItem(at: directoryURL)
            return true
        } catch {
            return false
        }
    }

    private func sideURL(
        comparisonDirectoryURL: URL,
        side: String,
        defaultFileName: String,
        sourceFileName: String?
    ) throws -> URL {
        guard let sourceFileName,
              !sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return comparisonDirectoryURL.appendingPathComponent(defaultFileName)
        }

        let sideDirectoryURL = comparisonDirectoryURL
            .appendingPathComponent(side, isDirectory: true)
        try fileManager.createDirectory(
            at: sideDirectoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return sideDirectoryURL.appendingPathComponent(
            sanitizedFileName(sourceFileName, fallback: defaultFileName)
        )
    }

    private func sanitizedFileName(_ fileName: String, fallback: String) -> String {
        let lastComponent = URL(fileURLWithPath: fileName).lastPathComponent
        let invalidCharacters = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let sanitizedScalars = lastComponent.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : String(scalar)
        }
        let sanitized = sanitizedScalars.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return fallback
        }
        return sanitized
    }

    private func writeReadOnly(_ text: String, to fileURL: URL) throws {
        try text.write(to: fileURL, atomically: false, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: fileURL.path
        )
    }
}
