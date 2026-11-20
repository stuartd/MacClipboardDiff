import Foundation

nonisolated struct ReleaseVersion: Sendable {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#
    )

    let tag: String
    private let numbers: [Substring]
    private let prerelease: [Substring]

    var displayName: String { String(tag.dropFirst()) }

    init?(tag: String) {
        guard tag.utf8.count <= 256,
              let match = Self.pattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        let prerelease = Range(match.range(at: 5), in: tag)
            .map { tag[$0].split(separator: ".") } ?? []
        guard !prerelease.contains(where: { $0.count > 1 && $0.first == "0" && Self.isNumeric($0) }) else {
            return nil
        }
        self.tag = tag
        numbers = (1...4).compactMap { Range(match.range(at: $0), in: tag).map { tag[$0] } }
        self.prerelease = prerelease
    }

    func isNewer(than other: ReleaseVersion) -> Bool {
        for (left, right) in zip(numbers, other.numbers) where left != right {
            return Self.numberIsGreater(left, than: right)
        }
        if numbers.count != other.numbers.count {
            return numbers.count > other.numbers.count
        }
        if prerelease.isEmpty || other.prerelease.isEmpty {
            return prerelease.isEmpty && !other.prerelease.isEmpty
        }
        for (left, right) in zip(prerelease, other.prerelease) where left != right {
            switch (Self.isNumeric(left), Self.isNumeric(right)) {
            case (true, true): return Self.numberIsGreater(left, than: right)
            case (true, false): return false
            case (false, true): return true
            case (false, false): return left > right
            }
        }
        return prerelease.count > other.prerelease.count
    }

    private static func isNumeric(_ value: Substring) -> Bool {
        value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func numberIsGreater(_ left: Substring, than right: Substring) -> Bool {
        if left.count != right.count { return left.count > right.count }
        return left > right
    }
}
