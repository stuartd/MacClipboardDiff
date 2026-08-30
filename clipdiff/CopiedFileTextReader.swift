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
        "kext", "mpkg", "o", "pkg", "so", "xpc", "zip"
    ]

    private let maximumTextFileBytes: Int

    init(maximumTextFileBytes: Int = CopiedFileTextReader.defaultMaximumTextFileBytes) {
        precondition(maximumTextFileBytes > 0)
        self.maximumTextFileBytes = maximumTextFileBytes
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

    func readFile(at fileURL: URL) -> CopiedFileText? {
        guard !Task.isCancelled, fileURL.isFileURL else { return nil }

        let standardizedURL = fileURL.standardizedFileURL
        let fileName = standardizedURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let path = standardizedURL.path
        let hasSecurityScope = standardizedURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return fallback(fileName: fileName, filePath: path, reason: "file not found")
        }

        if isDirectory.boolValue {
            return fallback(fileName: fileName, filePath: path, reason: "directory")
        }

        if Self.knownBinaryExtensions.contains(standardizedURL.pathExtension.lowercased()) {
            return fallback(fileName: fileName, filePath: path, reason: "binary file")
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            return fallback(fileName: fileName, filePath: path, reason: "file unreadable")
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0

            if fileSize == 0 {
                return fallback(fileName: fileName, filePath: path, reason: "empty file")
            }

            if fileSize > maximumTextFileBytes {
                return fallback(fileName: fileName, filePath: path, reason: "file too large")
            }

            guard !Task.isCancelled else { return nil }
            let data = try Data(contentsOf: standardizedURL, options: .mappedIfSafe)
            guard !Task.isCancelled else { return nil }
            guard !data.isEmpty else {
                return fallback(fileName: fileName, filePath: path, reason: "empty file")
            }
            guard data.count <= maximumTextFileBytes else {
                return fallback(fileName: fileName, filePath: path, reason: "file too large")
            }
            guard let text = decodeText(data) else {
                return fallback(fileName: fileName, filePath: path, reason: "binary file")
            }
            guard !text.isEmpty else {
                return fallback(fileName: fileName, filePath: path, reason: "empty file")
            }

            return CopiedFileText(text: text, fileName: fileName, filePath: path)
        } catch {
            let reason = FileManager.default.fileExists(atPath: path)
                ? "file unreadable"
                : "file not found"
            return fallback(fileName: fileName, filePath: path, reason: reason)
        }
    }

    private func decodeText(_ data: Data) -> String? {
        if let bomText = decodeByteOrderMarkedText(data) {
            return isTextLike(bomText) ? bomText : nil
        }

        if let encoding = detectByteOrderMarklessUTF16(data),
           let text = String(data: data, encoding: encoding),
           isTextLike(text) {
            return text
        }

        guard !looksBinary(data) else { return nil }

        if let text = String(data: data, encoding: .utf8), isTextLike(text) {
            return text
        }

        if let text = String(data: data, encoding: .windowsCP1252), isTextLike(text) {
            return text
        }

        return nil
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
            if (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) || byte == 0x7F {
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
               scalar != "\t", scalar != "\n", scalar != "\r" {
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
