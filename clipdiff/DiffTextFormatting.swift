import Foundation

struct DiffTextSlice: Equatable {
    let text: String
    let highlighted: Bool
}

enum DiffTextFormatting {
    /// Map extended-grapheme offsets before expanding tabs for display.
    /// These plain strings must never be parsed as Markdown or markup by the view.
    static func slices(_ source: String?, highlights: [HighlightRange]) -> [DiffTextSlice] {
        let text = source ?? ""
        guard !highlights.isEmpty else {
            return [DiffTextSlice(text: text.replacingOccurrences(of: "\t", with: "    "), highlighted: false)]
        }
        let characters = Array(text)
        var result: [DiffTextSlice] = []
        var position = 0
        func append(_ start: Int, _ end: Int, highlighted: Bool) {
            guard start < end else { return }
            result.append(DiffTextSlice(
                text: String(characters[start..<end]).replacingOccurrences(of: "\t", with: "    "),
                highlighted: highlighted
            ))
        }
        for range in highlights {
            append(position, range.start, highlighted: false)
            append(range.start, range.end, highlighted: true)
            position = range.end
        }
        append(position, characters.count, highlighted: false)
        return result
    }
}
