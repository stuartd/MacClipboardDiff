import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let capturedAt: Date

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
}

enum DiffKind {
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
            parts.append("\(changed) changed")
        }
        if inserted > 0 {
            parts.append("\(inserted) added")
        }
        if removed > 0 {
            parts.append("\(removed) removed")
        }
        return parts.joined(separator: ", ")
    }
}

struct DiffDocument: Identifiable {
    let id = UUID()
    let previous: ClipboardEntry
    let current: ClipboardEntry
    let rows: [DiffRow]
    let summary: DiffSummary
    let createdAt: Date

    var maxVisibleLineLength: Int {
        rows.reduce(0) { maxLength, row in
            max(maxLength, row.oldText?.count ?? 0, row.newText?.count ?? 0)
        }
    }
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
