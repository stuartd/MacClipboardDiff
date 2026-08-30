import Foundation

enum DiffEngine {
    static func makeDocument(previous: ClipboardEntry, current: ClipboardEntry) -> DiffDocument {
        let oldLines = TextLines.split(previous.text)
        let newLines = TextLines.split(current.text)
        let rows = makeRows(oldLines: oldLines, newLines: newLines)
        let labels = makeLabels(previous: previous, current: current)

        return DiffDocument(
            previous: entryWithoutSourcePath(previous),
            current: entryWithoutSourcePath(current),
            rows: rows,
            summary: summarize(rows),
            createdAt: Date(),
            labels: labels
        )
    }

    static func copyableDiff(for document: DiffDocument) -> String {
        var lines: [String] = [
            "--- \(document.labels.previous)",
            "+++ \(document.labels.current)"
        ]

        for row in document.rows {
            switch row.kind {
            case .equal:
                lines.append("  \(row.oldText ?? "")")
            case .removed:
                lines.append("- \(row.oldText ?? "")")
            case .inserted:
                lines.append("+ \(row.newText ?? "")")
            case .changed:
                lines.append("- \(row.oldText ?? "")")
                lines.append("+ \(row.newText ?? "")")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func makeLabels(
        previous: ClipboardEntry,
        current: ClipboardEntry
    ) -> DiffSideLabels {
        let fileLabels = ClipboardEntryDisplay.resolveFileLabels(
            previous: previous,
            current: current
        )
        return DiffSideLabels(
            previous: sideLabel(defaultLabel: "Previous clipboard", fileLabel: fileLabels.previous),
            current: sideLabel(defaultLabel: "Current clipboard", fileLabel: fileLabels.current)
        )
    }

    private static func sideLabel(defaultLabel: String, fileLabel: String?) -> String {
        guard let fileLabel, !fileLabel.isEmpty else { return defaultLabel }
        return "\(defaultLabel) — \(fileLabel)"
    }

    private static func entryWithoutSourcePath(_ entry: ClipboardEntry) -> ClipboardEntry {
        ClipboardEntry(
            id: entry.id,
            text: entry.text,
            capturedAt: entry.capturedAt,
            sourceFileName: entry.sourceFileName
        )
    }

    private static func makeRows(oldLines: [String], newLines: [String]) -> [DiffRow] {
        let difference = newLines.difference(from: oldLines)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()

        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertedOffsets.insert(offset)
            }
        }

        var rows: [DiffRow] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            var removedBlock: [(offset: Int, text: String)] = []
            while oldIndex < oldLines.count && removedOffsets.contains(oldIndex) {
                removedBlock.append((oldIndex, oldLines[oldIndex]))
                oldIndex += 1
            }

            var insertedBlock: [(offset: Int, text: String)] = []
            while newIndex < newLines.count && insertedOffsets.contains(newIndex) {
                insertedBlock.append((newIndex, newLines[newIndex]))
                newIndex += 1
            }

            if !removedBlock.isEmpty || !insertedBlock.isEmpty {
                appendChangedRows(
                    removedBlock: removedBlock,
                    insertedBlock: insertedBlock,
                    to: &rows
                )
                continue
            }

            if oldIndex < oldLines.count && newIndex < newLines.count {
                rows.append(
                    DiffRow(
                        oldLineNumber: oldIndex + 1,
                        newLineNumber: newIndex + 1,
                        oldText: oldLines[oldIndex],
                        newText: newLines[newIndex],
                        kind: .equal
                    )
                )
                oldIndex += 1
                newIndex += 1
                continue
            }

            if oldIndex < oldLines.count {
                rows.append(
                    DiffRow(
                        oldLineNumber: oldIndex + 1,
                        newLineNumber: nil,
                        oldText: oldLines[oldIndex],
                        newText: nil,
                        kind: .removed
                    )
                )
                oldIndex += 1
                continue
            }

            if newIndex < newLines.count {
                rows.append(
                    DiffRow(
                        oldLineNumber: nil,
                        newLineNumber: newIndex + 1,
                        oldText: nil,
                        newText: newLines[newIndex],
                        kind: .inserted
                    )
                )
                newIndex += 1
            }
        }

        return rows
    }

    private static func appendChangedRows(
        removedBlock: [(offset: Int, text: String)],
        insertedBlock: [(offset: Int, text: String)],
        to rows: inout [DiffRow]
    ) {
        let pairedCount = min(removedBlock.count, insertedBlock.count)

        for index in 0..<pairedCount {
            let removed = removedBlock[index]
            let inserted = insertedBlock[index]

            rows.append(
                DiffRow(
                    oldLineNumber: removed.offset + 1,
                    newLineNumber: inserted.offset + 1,
                    oldText: removed.text,
                    newText: inserted.text,
                    kind: .changed
                )
            )
        }

        if removedBlock.count > pairedCount {
            for removed in removedBlock[pairedCount...] {
                rows.append(
                    DiffRow(
                        oldLineNumber: removed.offset + 1,
                        newLineNumber: nil,
                        oldText: removed.text,
                        newText: nil,
                        kind: .removed
                    )
                )
            }
        }

        if insertedBlock.count > pairedCount {
            for inserted in insertedBlock[pairedCount...] {
                rows.append(
                    DiffRow(
                        oldLineNumber: nil,
                        newLineNumber: inserted.offset + 1,
                        oldText: nil,
                        newText: inserted.text,
                        kind: .inserted
                    )
                )
            }
        }
    }

    private static func summarize(_ rows: [DiffRow]) -> DiffSummary {
        var inserted = 0
        var removed = 0
        var changed = 0
        var unchanged = 0

        for row in rows {
            switch row.kind {
            case .equal:
                unchanged += 1
            case .inserted:
                inserted += 1
            case .removed:
                removed += 1
            case .changed:
                changed += 1
            }
        }

        return DiffSummary(
            inserted: inserted,
            removed: removed,
            changed: changed,
            unchanged: unchanged
        )
    }
}
