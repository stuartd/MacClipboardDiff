import AppKit
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
                EmptyDiffView(shortcut: controller.globalShortcut.displayString)
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
        VStack(alignment: .leading, spacing: 8) {
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
            }

            Toggle("Ignore spacing", isOn: $controller.ignoreSpacing)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Ignore leading and trailing whitespace and treat internal whitespace runs as one space. Original text is preserved.")
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    SideBySideHeader(
                        previousLabel: document.labels.previous,
                        currentLabel: document.labels.current,
                        sideWidth: sideWidth
                    )

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
    let previousLabel: String
    let currentLabel: String
    let sideWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            headerCell(previousLabel)
            Divider()
            headerCell(currentLabel)
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
                text: row.oldText, highlights: row.oldHighlights, highlight: .red
            )

            Divider()

            side(
                lineNumber: row.newLineNumber,
                text: row.newText, highlights: row.newHighlights, highlight: .green
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

    private func side(
        lineNumber: Int?, text: String?, highlights: [HighlightRange], highlight: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            diffText(text, highlights: highlights, highlight: highlight)
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    unifiedLine(
                        "--- \(document.labels.previous)",
                        background: Color(nsColor: .controlBackgroundColor)
                    )
                    unifiedLine(
                        "+++ \(document.labels.current)",
                        background: Color(nsColor: .controlBackgroundColor)
                    )

                    ForEach(document.rows) { row in
                        switch row.kind {
                        case .equal:
                            unifiedLine("  \(row.oldText ?? "")", background: .clear)
                        case .removed:
                            unifiedLine(row.oldText ?? "", prefix: "- ", highlights: row.oldHighlights, highlight: .red, background: Color.red.opacity(0.13))
                        case .inserted:
                            unifiedLine(row.newText ?? "", prefix: "+ ", highlights: row.newHighlights, highlight: .green, background: Color.green.opacity(0.13))
                        case .changed:
                            unifiedLine(row.oldText ?? "", prefix: "- ", highlights: row.oldHighlights, highlight: .red, background: Color.red.opacity(0.13))
                            unifiedLine(row.newText ?? "", prefix: "+ ", highlights: row.newHighlights, highlight: .green, background: Color.green.opacity(0.13))
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func unifiedLine(
        _ text: String, prefix: String = "", highlights: [HighlightRange] = [],
        highlight: Color = .clear, background: Color
    ) -> some View {
        diffText(text, prefix: prefix, highlights: highlights, highlight: highlight)
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
    let shortcut: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("No Diff")
                .font(.title3.weight(.semibold))

            Text("Copy two text values, then press \(shortcut).")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Use AppKit for inline background attributes on macOS 13. Plain rows retain
/// SwiftUI Text; highlighted rows use a single native, selectable paragraph.
@ViewBuilder
private func diffText(
    _ text: String?, prefix: String = "", highlights: [HighlightRange], highlight: Color
) -> some View {
    if highlights.isEmpty {
        Text(verbatim: prefix + (text ?? "").replacingOccurrences(of: "\t", with: "    "))
    } else {
        HighlightedDiffText(text: text, prefix: prefix, highlights: highlights, highlight: highlight)
    }
}

private struct HighlightedDiffText: NSViewRepresentable {
    let text: String?
    let prefix: String
    let highlights: [HighlightRange]
    let highlight: Color

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        let attributed = NSMutableAttributedString(string: prefix, attributes: attributes)
        for slice in DiffTextFormatting.slices(text, highlights: highlights) {
            var runAttributes = attributes
            if slice.highlighted {
                runAttributes[.backgroundColor] = NSColor(highlight).withAlphaComponent(0.3)
            }
            attributed.append(NSAttributedString(string: slice.text, attributes: runAttributes))
        }
        if view.textStorage?.isEqual(to: attributed) != true {
            view.textStorage?.setAttributedString(attributed)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lineHeight = layout.defaultLineHeight(for: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        return CGSize(width: width, height: max(lineHeight, ceil(layout.usedRect(for: container).height)))
    }
}
