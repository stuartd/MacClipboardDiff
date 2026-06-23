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

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = max(320, (proxy.size.width - 1) / 2)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    SideBySideHeader(sideWidth: sideWidth)

                    ForEach(document.rows) { row in
                        SideBySideRow(row: row, sideWidth: sideWidth)
                    }
                }
                .frame(width: max(proxy.size.width, (sideWidth * 2) + 1), alignment: .leading)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct SideBySideHeader: View {
    let sideWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            headerCell("Previous")
            Divider()
            headerCell("Current")
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerCell(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .frame(width: sideWidth, alignment: .leading)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct SideBySideRow: View {
    let row: DiffRow
    let sideWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            side(
                lineNumber: row.oldLineNumber,
                text: row.oldText
            )

            Divider()

            side(
                lineNumber: row.newLineNumber,
                text: row.newText
            )
        }
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                oldBackground.frame(width: sideWidth)
                Color.clear.frame(width: 1)
                newBackground.frame(width: sideWidth)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 0.5)
        }
    }

    private func side(lineNumber: Int?, text: String?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Text((text ?? "").displayTabs)
                .foregroundStyle(text == nil ? .clear : .primary)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .frame(width: sideWidth, alignment: .leading)
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.vertical, 3)
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
        GeometryReader { proxy in
            let contentWidth = max(320, proxy.size.width)

            ScrollView(.vertical) {
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
                .frame(width: contentWidth, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func unifiedLine(_ text: String, background: Color) -> some View {
        Text(text.displayTabs)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
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
