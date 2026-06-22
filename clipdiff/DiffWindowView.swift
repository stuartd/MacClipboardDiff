import SwiftUI

struct DiffWindowView: View {
    @ObservedObject var controller: ClipDiffController

    var body: some View {
        Group {
            if let document = controller.activeDiff {
                VStack(spacing: 0) {
                    DiffHeaderView(document: document, controller: controller)

                    Divider()

                    if controller.viewMode == .sideBySide {
                        SideBySideDiffView(document: document)
                    } else {
                        UnifiedDiffView(document: document)
                    }
                }
            } else {
                EmptyDiffView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DiffHeaderView: View {
    let document: DiffDocument
    @ObservedObject var controller: ClipDiffController

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clipboard Diff")
                    .font(.headline)

                Text(document.summary.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("View", selection: $controller.viewMode) {
                ForEach(DiffViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Button {
                controller.copyActiveDiff()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .help("Copy diff")

            Button {
                controller.clearCapturedText()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Clear captured text")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct SideBySideDiffView: View {
    let document: DiffDocument

    private var columnWidth: CGFloat {
        let estimated = CGFloat(document.maxVisibleLineLength) * 7.2 + 24
        return min(max(460, estimated), 1400)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                SideBySideHeader(columnWidth: columnWidth)

                ForEach(document.rows) { row in
                    SideBySideRow(row: row, columnWidth: columnWidth)
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct SideBySideHeader: View {
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            headerCell("Previous", columnWidth: columnWidth)
            Divider()
            headerCell("Current", columnWidth: columnWidth)
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerCell(_ title: String, columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Text(title)
                .frame(width: columnWidth, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct SideBySideRow: View {
    let row: DiffRow
    let columnWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            side(
                lineNumber: row.oldLineNumber,
                text: row.oldText,
                background: oldBackground
            )

            Divider()

            side(
                lineNumber: row.newLineNumber,
                text: row.newText,
                background: newBackground
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 0.5)
        }
    }

    private func side(lineNumber: Int?, text: String?, background: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Text((text ?? "").displayTabs)
                .foregroundStyle(text == nil ? .clear : .primary)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
                .padding(.horizontal, 8)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.vertical, 3)
        .background(background)
    }

    private var oldBackground: Color {
        switch row.kind {
        case .removed, .changed:
            Color.red.opacity(0.13)
        case .inserted:
            Color.clear
        case .equal:
            Color.clear
        }
    }

    private var newBackground: Color {
        switch row.kind {
        case .inserted, .changed:
            Color.green.opacity(0.13)
        case .removed:
            Color.clear
        case .equal:
            Color.clear
        }
    }
}

private struct UnifiedDiffView: View {
    let document: DiffDocument

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                unifiedLine("--- Previous clipboard", background: Color(nsColor: .controlBackgroundColor))
                unifiedLine("+++ Current clipboard", background: Color(nsColor: .controlBackgroundColor))

                ForEach(document.rows) { row in
                    switch row.kind {
                    case .equal:
                        unifiedLine("  \(row.oldText ?? "")", background: .clear)
                    case .removed:
                        unifiedLine("- \(row.oldText ?? "")", background: Color.red.opacity(0.13))
                    case .inserted:
                        unifiedLine("+ \(row.newText ?? "")", background: Color.green.opacity(0.13))
                    case .changed:
                        unifiedLine("- \(row.oldText ?? "")", background: Color.red.opacity(0.13))
                        unifiedLine("+ \(row.newText ?? "")", background: Color.green.opacity(0.13))
                    }
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func unifiedLine(_ text: String, background: Color) -> some View {
        Text(text.displayTabs)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minWidth: 900, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background(background)
    }
}

private struct EmptyDiffView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("No Diff")
                .font(.title3.weight(.semibold))

            Text("Copy two text values, then press Option-Command-D.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension String {
    var displayTabs: String {
        replacingOccurrences(of: "\t", with: "    ")
    }
}
