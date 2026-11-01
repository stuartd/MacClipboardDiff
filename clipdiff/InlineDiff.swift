import Foundation

/// One instance per document; changed rows share a bounded refinement budget.
struct InlineDiff {
    private static let maximumPairBytes = 16_384
    private static let maximumSearchCells = 65_536
    private var remainingWork = 2_000_000
    let ignoreSpacing: Bool

    init(ignoreSpacing: Bool) {
        self.ignoreSpacing = ignoreSpacing
    }

    mutating func highlight(_ row: DiffRow) -> DiffRow {
        guard row.kind == .changed, let old = row.oldText, let current = row.newText else { return row }
        let bytes = old.utf8.count + current.utf8.count
        guard bytes <= Self.maximumPairBytes, bytes <= remainingWork else { return row }
        remainingWork -= bytes

        var budget = min(Self.maximumSearchCells, remainingWork)
        let initialBudget = budget
        let oldUnits = Self.units(old, normalize: ignoreSpacing)
        let newUnits = Self.units(current, normalize: ignoreSpacing)
        let oldTokens = Self.tokens(oldUnits)
        let newTokens = Self.tokens(newUnits)
        let matches = Self.align(oldTokens, newTokens, budget: &budget)
        var oldMatched = Array(repeating: false, count: oldUnits.count)
        var newMatched = Array(repeating: false, count: newUnits.count)
        var oldStart = 0
        var newStart = 0

        for (oldIndex, newIndex) in matches + [(oldTokens.count, newTokens.count)] {
            let oldEnd = oldIndex == oldTokens.count ? oldUnits.count : oldTokens[oldIndex].start
            let newEnd = newIndex == newTokens.count ? newUnits.count : newTokens[newIndex].start
            let refined = Self.align(
                Array(oldUnits[oldStart..<oldEnd]), Array(newUnits[newStart..<newEnd]),
                budget: &budget, weighted: false
            )
            for (oldUnit, newUnit) in refined {
                oldMatched[oldStart + oldUnit] = true
                newMatched[newStart + newUnit] = true
            }
            if oldIndex == oldTokens.count { break }

            let oldToken = oldTokens[oldIndex]
            let newToken = newTokens[newIndex]
            for index in oldToken.start..<oldToken.end { oldMatched[index] = true }
            for index in newToken.start..<newToken.end { newMatched[index] = true }
            oldStart = oldToken.end
            newStart = newToken.end
        }
        remainingWork -= initialBudget - budget

        var highlighted = row
        highlighted.oldHighlights = Self.changedRanges(oldUnits, matched: oldMatched)
        highlighted.newHighlights = Self.changedRanges(newUnits, matched: newMatched)
        return highlighted
    }

    static func normalizeSpacing(_ text: String) -> String {
        units(text, normalize: true).map(\.text).joined()
    }

    // Swift String equality normalizes canonically. Diff equality must be ordinal,
    // matching Windows and preserving composed/decomposed changes as actual edits.
    static func equal(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private struct Unit {
        let text: String
        let start: Int
        let end: Int
        let weight: Int
    }

    private static func units(_ text: String, normalize: Bool) -> [Unit] {
        var result: [Unit] = []
        for (index, character) in text.enumerated() {
            let value = String(character)
            if normalize && isWhitespace(value) {
                if let last = result.last {
                    if last.text == " " {
                        result[result.count - 1] = Unit(text: " ", start: last.start, end: index + 1, weight: 1)
                    } else {
                        result.append(Unit(text: " ", start: index, end: index + 1, weight: 1))
                    }
                }
            } else {
                result.append(Unit(text: value, start: index, end: index + 1, weight: 1))
            }
        }
        if normalize && result.last?.text == " " { result.removeLast() }
        return result
    }

    private static func isWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    private static func category(_ text: String) -> Int {
        if isWhitespace(text) { return 0 }
        guard let first = text.unicodeScalars.first else { return 2 }
        if first == "_" { return 1 }
        switch first.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return 1
        default:
            return 2
        }
    }

    private static func tokens(_ units: [Unit]) -> [Unit] {
        var tokens: [Unit] = []
        var start = 0
        while start < units.count {
            let kind = category(units[start].text)
            var end = start + 1
            while kind != 2 && end < units.count && category(units[end].text) == kind { end += 1 }
            tokens.append(Unit(
                text: units[start..<end].map(\.text).joined(), start: start, end: end,
                weight: kind == 0 ? 1 : max(2, end - start)
            ))
            start = end
        }
        return tokens
    }

    private static func align(
        _ old: [Unit], _ current: [Unit], budget: inout Int, weighted: Bool = true
    ) -> [(Int, Int)] {
        var matches: [(Int, Int)] = []
        var prefix = 0
        while prefix < old.count && prefix < current.count && equal(old[prefix].text, current[prefix].text) {
            matches.append((prefix, prefix))
            prefix += 1
        }
        var oldEnd = old.count
        var newEnd = current.count
        while oldEnd > prefix && newEnd > prefix && equal(old[oldEnd - 1].text, current[newEnd - 1].text) {
            oldEnd -= 1
            newEnd -= 1
        }

        let n = oldEnd - prefix
        let m = newEnd - prefix
        let cells = (n + 1) * (m + 1)
        if n > 0 && m > 0 && cells <= budget {
            budget -= cells
            let width = m + 1
            var scores = Array(repeating: 0, count: cells)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    scores[i * width + j] = equal(old[prefix + i].text, current[prefix + j].text)
                        ? scores[(i + 1) * width + j + 1] + (weighted ? old[prefix + i].weight : 1)
                        : max(scores[(i + 1) * width + j], scores[i * width + j + 1])
                }
            }
            var x = 0
            var y = 0
            while x < n && y < m {
                if equal(old[prefix + x].text, current[prefix + y].text) {
                    matches.append((prefix + x, prefix + y))
                    x += 1
                    y += 1
                } else if scores[(x + 1) * width + y] >= scores[x * width + y + 1] {
                    x += 1 // Same tie break as Windows: advance the original side.
                } else {
                    y += 1
                }
            }
        }
        while oldEnd < old.count {
            matches.append((oldEnd, newEnd))
            oldEnd += 1
            newEnd += 1
        }
        return matches
    }

    private static func changedRanges(_ units: [Unit], matched: [Bool]) -> [HighlightRange] {
        var ranges: [HighlightRange] = []
        for (index, unit) in units.enumerated() where !matched[index] {
            if let last = ranges.last, last.end == unit.start {
                ranges[ranges.count - 1] = HighlightRange(start: last.start, end: unit.end)
            } else {
                ranges.append(HighlightRange(start: unit.start, end: unit.end))
            }
        }
        return ranges
    }
}
