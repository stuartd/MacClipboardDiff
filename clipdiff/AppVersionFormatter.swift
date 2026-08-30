import Foundation

enum AppVersionFormatter {
    static func applicationVersion(buildNumber: String?, commit: String?) -> String {
        let build = buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortCommit = shortCommit(commit)

        switch (build?.isEmpty == false ? build : nil, shortCommit) {
        case (.some(let build), .some(let commit)):
            return "\(build) · \(commit)"
        case (.some(let build), .none):
            return build
        case (.none, .some(let commit)):
            return commit
        case (.none, .none):
            return "Unknown"
        }
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
        return String(trimmed.prefix(7))
    }
}
