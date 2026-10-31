import Foundation

enum AppVersionFormatter {
    static func aboutVersion(releaseTag: String?, commit: String?) -> String {
        if let tag = releaseTag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        }

        return shortCommit(commit) ?? "Unavailable"
    }

    static func shortCommit(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 7,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return (48...57).contains(value) ||
                      (65...70).contains(value) ||
                      (97...102).contains(value)
              }) else {
            return nil
        }
        return String(trimmed.prefix(8))
    }
}
