import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let capturedAt: Date
    let sourceFileName: String?
    let sourceFilePath: String?

    init(
        id: UUID = UUID(),
        text: String,
        capturedAt: Date,
        sourceFileName: String? = nil,
        sourceFilePath: String? = nil
    ) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
        self.sourceFileName = sourceFileName
        self.sourceFilePath = sourceFilePath
    }

    var lineCount: Int {
        TextLines.split(text).count
    }

    var characterCount: Int {
        text.count
    }

    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "Blank text" }

        if collapsed.count <= 120 {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<endIndex]) + "..."
    }

    func displayPreview(fileLabel: String? = nil) -> String {
        let label = fileLabel ?? sourceFileName
        guard let label, !label.isEmpty else { return preview }
        return "\(label) — \(preview)"
    }
}

struct ClipboardFileLabels: Equatable {
    let previous: String?
    let current: String?
}

enum ClipboardEntryDisplay {
    static func resolveFileLabels(
        previous: ClipboardEntry?,
        current: ClipboardEntry?
    ) -> ClipboardFileLabels {
        let previousLabel = usableFileName(previous)
        let currentLabel = usableFileName(current)

        guard let previousLabel,
              let currentLabel,
              previousLabel == currentLabel,
              let previousPath = usableFilePath(previous),
              let currentPath = usableFilePath(current),
              previousPath != currentPath else {
            return ClipboardFileLabels(previous: previousLabel, current: currentLabel)
        }

        let previousSegments = pathSegments(previousPath)
        let currentSegments = pathSegments(currentPath)
        let maximumDepth = max(previousSegments.count, currentSegments.count)

        guard maximumDepth >= 2 else {
            return ClipboardFileLabels(previous: previousLabel, current: currentLabel)
        }

        for depth in 2...maximumDepth {
            let previousSuffix = suffix(previousSegments, depth: depth)
            let currentSuffix = suffix(currentSegments, depth: depth)
            if previousSuffix != currentSuffix {
                return ClipboardFileLabels(previous: previousSuffix, current: currentSuffix)
            }
        }

        return ClipboardFileLabels(previous: previousLabel, current: currentLabel)
    }

    private static func usableFileName(_ entry: ClipboardEntry?) -> String? {
        guard let name = entry?.sourceFileName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return name
    }

    private static func usableFilePath(_ entry: ClipboardEntry?) -> String? {
        guard let path = entry?.sourceFilePath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }

    private static func pathSegments(_ path: String) -> [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: true)
    }

    private static func suffix(_ segments: [Substring], depth: Int) -> String {
        segments.suffix(depth).joined(separator: "/")
    }
}

enum DiffKind: Equatable {
    case equal
    case inserted
    case removed
    case changed
}

struct DiffRow: Identifiable {
    let id = UUID()
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let oldText: String?
    let newText: String?
    let kind: DiffKind
}

struct DiffSummary {
    let inserted: Int
    let removed: Int
    let changed: Int
    let unchanged: Int

    var hasDifferences: Bool {
        inserted > 0 || removed > 0 || changed > 0
    }

    var label: String {
        guard hasDifferences else { return "No differences" }

        var parts: [String] = []
        if changed > 0 {
            parts.append(lineLabel(count: changed, action: "changed"))
        }
        if inserted > 0 {
            parts.append(lineLabel(count: inserted, action: "added"))
        }
        if removed > 0 {
            parts.append(lineLabel(count: removed, action: "removed"))
        }
        return parts.joined(separator: ", ")
    }

    private func lineLabel(count: Int, action: String) -> String {
        "\(count) \(action) \(count == 1 ? "line" : "lines")"
    }
}

struct DiffSideLabels: Equatable {
    let previous: String
    let current: String
}

struct DiffDocument: Identifiable {
    let id = UUID()
    let previous: ClipboardEntry
    let current: ClipboardEntry
    let rows: [DiffRow]
    let summary: DiffSummary
    let createdAt: Date
    let labels: DiffSideLabels
}

enum DiffViewMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by Side"
    case unified = "Unified"

    var id: String { rawValue }
}

enum TextLines {
    static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}
