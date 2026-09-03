import Foundation

struct FinderComparisonRequest: Equatable {
    static let scheme = "clipdiff"
    static let host = "compare-selected-files"

    let fileURLs: [URL]

    init?(fileURLs: [URL]) {
        guard fileURLs.count == 2,
              fileURLs.allSatisfy(\.isFileURL) else {
            return nil
        }
        self.fileURLs = fileURLs
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == Self.host else {
            return nil
        }

        let fileValues = (components.queryItems ?? [])
            .filter { $0.name == "file" }
            .compactMap(\.value)
        guard fileValues.count == 2 else { return nil }

        let fileURLs = fileValues.compactMap(URL.init(string:))
        guard fileURLs.count == fileValues.count else { return nil }

        self.init(fileURLs: fileURLs)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = fileURLs.map {
            URLQueryItem(name: "file", value: $0.absoluteString)
        }
        return components.url
    }
}
