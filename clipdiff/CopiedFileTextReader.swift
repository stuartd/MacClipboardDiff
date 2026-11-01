import Foundation

struct CopiedFileText: Equatable, Sendable {
    let text: String
    let fileName: String
    let filePath: String

    var capturedValue: CapturedClipboardValue {
        CapturedClipboardValue(
            text: text,
            sourceFileName: fileName,
            sourceFilePath: filePath
        )
    }
}

nonisolated struct CopiedFileTextReader: Sendable {
    static let defaultMaximumTextFileBytes = 16 * 1024 * 1024

    private static let knownBinaryExtensions: Set<String> = [
        "a", "app", "bundle", "class", "dmg", "dylib", "framework", "jar",
        "kext", "mpkg", "o", "pkg", "so", "xpc", "zip",
        "appx", "appxbundle", "com", "cpl", "dll", "drv", "efi", "exe",
        "msi", "msix", "msixbundle", "msp", "mst", "mui", "ocx", "scr", "sys"
    ]

    // Content signatures also catch renamed binaries whose bytes can look textual,
    // such as PDF and GIF. Check these before BOM-less text heuristics.
    private static let knownBinarySignatures: [[UInt8]] = [
        [0x25, 0x50, 0x44, 0x46, 0x2D],                         // PDF
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],       // PNG
        [0xFF, 0xD8, 0xFF],                                     // JPEG
        [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],                   // GIF87a
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],                   // GIF89a
        [0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06],     // ZIP
        [0x50, 0x4B, 0x07, 0x08],
        [0x1F, 0x8B], [0x42, 0x5A, 0x68],                       // GZip, BZip2
        [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],                   // 7-Zip
        [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07],                   // RAR
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],       // OLE
        [0x7F, 0x45, 0x4C, 0x46],                               // ELF
        [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],     // Java / fat Mach-O
        [0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE],     // Mach-O
        [0xFE, 0xED, 0xFA, 0xCF], [0xCF, 0xFA, 0xED, 0xFE]
    ]

    private let maximumTextFileBytes: Int
    private let aliasTargetResolver: @Sendable (URL) throws -> URL?

    init(
        maximumTextFileBytes: Int = CopiedFileTextReader.defaultMaximumTextFileBytes,
        resolveAlias: @escaping @Sendable (URL) throws -> URL? = CopiedFileTextReader.systemAliasTarget
    ) {
        precondition(maximumTextFileBytes > 0)
        self.maximumTextFileBytes = maximumTextFileBytes
        aliasTargetResolver = resolveAlias
    }

    func readValues(from fileURLs: [URL]) async -> [CopiedFileText] {
        guard (1...2).contains(fileURLs.count) else { return [] }

        let readTask = Task.detached(priority: .userInitiated) { () -> [CopiedFileText] in
            var values: [CopiedFileText] = []
            for fileURL in fileURLs {
                guard !Task.isCancelled, let value = readFile(at: fileURL) else {
                    return [CopiedFileText]()
                }
                values.append(value)
            }
            return values
        }

        return await withTaskCancellationHandler {
            await readTask.value
        } onCancel: {
            readTask.cancel()
        }
    }

    /// Recognizes copied absolute paths before reading any file contents.
    /// Ordinary text (including malformed or mixed path lists) stays intact.
    /// Quoted paths opt into the same fallbacks as copied file objects.
    func readClipboardText(_ text: String) async -> ClipboardObservationContent {
        guard !Task.isCancelled else { return .nonText }
        guard let paths = Self.parseClipboardPaths(text) else {
            return .value(CapturedClipboardValue(text: text))
        }

        let readTask = Task.detached(priority: .userInitiated) { () -> ClipboardObservationContent in
            // Existence probes can block on mounted volumes, so keep them off
            // the main actor along with the reads. Validate the complete list
            // before reading it; never accept only one half of a pair.
            if paths.requiresExistingFiles {
                for path in paths.values {
                    guard !Task.isCancelled else { return .nonText }
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                          !isDirectory.boolValue else {
                        return .value(CapturedClipboardValue(text: text))
                    }
                }
            }

            guard (1...2).contains(paths.values.count) else { return .nonText }
            var values: [CapturedClipboardValue] = []
            for path in paths.values {
                guard !Task.isCancelled,
                      let value = readFile(at: URL(fileURLWithPath: path)) else {
                    return .nonText
                }
                values.append(value.capturedValue)
            }

            if values.count == 2 {
                return .pair(previous: values[0], current: values[1])
            }
            return .value(values[0])
        }

        return await withTaskCancellationHandler {
            await readTask.value
        } onCancel: {
            readTask.cancel()
        }
    }

    private struct ClipboardPaths: Sendable {
        let values: [String]
        let requiresExistingFiles: Bool
    }

    private static func parseClipboardPaths(_ text: String) -> ClipboardPaths? {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return nil }

        var paths: [String] = []
        var requiresExistingFiles = false
        for line in lines {
            let quoted = line.count >= 2 && line.hasPrefix("\"") && line.hasSuffix("\"")
            let path = quoted ? String(line.dropFirst().dropLast()) : line
            guard path.hasPrefix("/"),
                  !path.contains("\""),
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                return nil
            }
            paths.append(path)
            requiresExistingFiles = requiresExistingFiles || !quoted
        }
        return ClipboardPaths(values: paths, requiresExistingFiles: requiresExistingFiles)
    }

    func readFile(at fileURL: URL) -> CopiedFileText? {
        guard !Task.isCancelled, fileURL.isFileURL else { return nil }
        let source = fileURL.standardizedFileURL
        #if os(macOS)
        let hasSecurityScope = source.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { source.stopAccessingSecurityScopedResource() }
        }
        #endif

        guard FileManager.default.fileExists(atPath: source.path) else {
            return fallback(fileName: source.lastPathComponent, filePath: source.path, reason: "file not found")
        }
        do {
            var target = source
            var visited: Set<String> = []
            var aliasCount = 0
            while true {
                guard !Task.isCancelled else { return nil }
                guard visited.insert(target.path).inserted else { throw CocoaError(.fileReadCorruptFile) }
                guard let next = try aliasTargetResolver(target) else { break }
                guard aliasCount < 8, next.isFileURL else { throw CocoaError(.fileReadCorruptFile) }
                aliasCount += 1
                target = next.standardizedFileURL
            }
            return readResolvedFile(at: target)
        } catch {
            guard !Task.isCancelled else { return nil }
            // Never decode an alias record as clipboard text when resolution fails.
            return fallback(fileName: source.lastPathComponent, filePath: source.path, reason: "file unreadable")
        }
    }

    private static func systemAliasTarget(_ fileURL: URL) throws -> URL? {
        #if os(macOS)
        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() }
        }
        let metadata = try fileURL.resourceValues(forKeys: [.isAliasFileKey, .fileSizeKey])
        guard metadata.isAliasFile == true else { return nil }
        guard let size = metadata.fileSize, size <= defaultMaximumTextFileBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Resolve bookmark data in memory, without rewriting even a stale alias.
        let data = try URL.bookmarkData(withContentsOf: fileURL)
        guard data.count <= defaultMaximumTextFileBytes else { throw CocoaError(.fileReadCorruptFile) }
        var isStale = false
        return try URL(
            resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &isStale
        )
        #else
        return nil
        #endif
    }

    private func readResolvedFile(at fileURL: URL) -> CopiedFileText? {
        guard !Task.isCancelled, fileURL.isFileURL else { return nil }

        let standardizedURL = fileURL.standardizedFileURL
        let fileName = standardizedURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let path = standardizedURL.path
        #if os(macOS)
        let hasSecurityScope = standardizedURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
        }
        #endif

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return fallback(
                fileName: fileName,
                filePath: path,
                reason: "file not found"
            )
        }

        if isDirectory.boolValue {
            return fallback(
                fileName: fileName,
                filePath: path,
                reason: "directory"
            )
        }

        if Self.knownBinaryExtensions.contains(standardizedURL.pathExtension.lowercased()) {
            return fallback(fileName: fileName, filePath: path, reason: "binary file")
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            return fallback(
                fileName: fileName,
                filePath: path,
                reason: "file unreadable"
            )
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0

            if fileSize == 0 {
                return fallback(
                    fileName: fileName,
                    filePath: path,
                    reason: "empty file"
                )
            }

            if fileSize > maximumTextFileBytes {
                return fallback(
                    fileName: fileName,
                    filePath: path,
                    reason: "file too large"
                )
            }

            guard !Task.isCancelled else { return nil }
            let data = try Data(contentsOf: standardizedURL, options: .mappedIfSafe)
            guard !Task.isCancelled else { return nil }
            guard !data.isEmpty else {
                return fallback(
                    fileName: fileName,
                    filePath: path,
                    reason: "empty file"
                )
            }
            guard data.count <= maximumTextFileBytes else {
                return fallback(
                    fileName: fileName,
                    filePath: path,
                    reason: "file too large"
                )
            }
            guard let text = decodeText(data) else {
                return fallback(fileName: fileName, filePath: path, reason: "binary file")
            }
            guard !text.isEmpty else {
                return fallback(
                    fileName: fileName,
                    filePath: path,
                    reason: "empty file"
                )
            }

            return CopiedFileText(text: text, fileName: fileName, filePath: path)
        } catch {
            let reason = FileManager.default.fileExists(atPath: path)
                ? "file unreadable"
                : "file not found"
            return fallback(
                fileName: fileName,
                filePath: path,
                reason: reason
            )
        }
    }

    private func decodeText(_ data: Data) -> String? {
        if let bomText = decodeByteOrderMarkedText(data) {
            return isTextLike(bomText) ? bomText : nil
        }

        guard !Self.knownBinarySignatures.contains(where: { data.starts(with: $0) }) else { return nil }

        if let encoding = detectByteOrderMarklessUTF16(data),
           let text = String(data: data, encoding: encoding),
           isTextLike(text) {
            return text
        }

        guard !looksBinary(data) else { return nil }

        if let text = String(data: data, encoding: .utf8), isTextLike(text) {
            return text
        }

        if let text = decodeWindowsCP1252(data), isTextLike(text) {
            return text
        }

        return nil
    }

    private func decodeWindowsCP1252(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }

        // swift-corelibs-foundation does not provide this conversion on every
        // platform used by the portable test suite.
        let controls: [UInt8: UnicodeScalar] = [
            0x80: "€", 0x82: "‚", 0x83: "ƒ", 0x84: "„", 0x85: "…",
            0x86: "†", 0x87: "‡", 0x88: "ˆ", 0x89: "‰", 0x8A: "Š",
            0x8B: "‹", 0x8C: "Œ", 0x8E: "Ž", 0x91: "‘", 0x92: "’",
            0x93: "“", 0x94: "”", 0x95: "•", 0x96: "–", 0x97: "—",
            0x98: "˜", 0x99: "™", 0x9A: "š", 0x9B: "›", 0x9C: "œ",
            0x9E: "ž", 0x9F: "Ÿ"
        ]
        var scalars = String.UnicodeScalarView()
        for byte in data {
            if let scalar = controls[byte] {
                scalars.append(scalar)
            } else if let scalar = UnicodeScalar(UInt32(byte)) {
                scalars.append(scalar)
            } else {
                return nil
            }
        }
        return String(scalars)
    }

    private func decodeByteOrderMarkedText(_ data: Data) -> String? {
        let candidates: [(signature: [UInt8], encoding: String.Encoding)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFE, 0xFF], .utf16BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian)
        ]

        for candidate in candidates where data.starts(with: candidate.signature) {
            return String(
                data: Data(data.dropFirst(candidate.signature.count)),
                encoding: candidate.encoding
            )
        }

        return nil
    }

    private func detectByteOrderMarklessUTF16(_ data: Data) -> String.Encoding? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else { return nil }

        let pairCount = min(data.count / 2, 2_048)
        var evenZeros = 0
        var oddZeros = 0

        for pair in 0..<pairCount {
            if data[pair * 2] == 0 { evenZeros += 1 }
            if data[(pair * 2) + 1] == 0 { oddZeros += 1 }
        }

        if oddZeros * 10 >= pairCount * 6, evenZeros * 10 <= pairCount {
            return .utf16LittleEndian
        }

        if evenZeros * 10 >= pairCount * 6, oddZeros * 10 <= pairCount {
            return .utf16BigEndian
        }

        return nil
    }

    private func looksBinary(_ data: Data) -> Bool {
        let inspected = data.prefix(8_192)
        var suspiciousControls = 0

        for byte in inspected {
            if byte == 0 { return true }
            if (byte < 0x20 && byte != 0x08 && byte != 0x09 && byte != 0x0A && byte != 0x0D && byte != 0x1B) || byte == 0x7F {
                suspiciousControls += 1
            }
        }

        return suspiciousControls > max(1, inspected.count / 100)
    }

    private func isTextLike(_ text: String) -> Bool {
        var scalarCount = 0
        var suspiciousControls = 0

        for scalar in text.unicodeScalars {
            scalarCount += 1
            if scalar.value == 0 { return false }

            if CharacterSet.controlCharacters.contains(scalar),
               scalar != "\u{8}", scalar != "\t", scalar != "\n", scalar != "\r", scalar != "\u{1b}" {
                suspiciousControls += 1
            }
        }

        return suspiciousControls <= max(1, scalarCount / 100)
    }

    private func fallback(
        fileName: String,
        filePath: String,
        reason: String
    ) -> CopiedFileText {
        CopiedFileText(
            text: "\(fileName) (\(reason))",
            fileName: fileName,
            filePath: filePath
        )
    }
}
