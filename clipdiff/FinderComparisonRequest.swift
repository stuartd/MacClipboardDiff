import Foundation

struct FinderComparisonRequest: Equatable {
    static let scheme = "clipdiff"

    enum Operation: String, Equatable {
        case compareSelectedFiles = "compare-selected-files"
        case compareWithCurrent = "compare-with-current"

        var requiredFileCount: Int {
            switch self {
            case .compareSelectedFiles: 2
            case .compareWithCurrent: 1
            }
        }
    }

    let operation: Operation
    let fileURLs: [URL]

    init?(operation: Operation = .compareSelectedFiles, fileURLs: [URL]) {
        guard fileURLs.count == operation.requiredFileCount,
              fileURLs.allSatisfy(\.isFileURL) else {
            return nil
        }
        self.operation = operation
        self.fileURLs = fileURLs
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              let host = components.host?.lowercased(),
              let operation = Operation(rawValue: host),
              components.path.isEmpty,
              components.fragment == nil else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard queryItems.allSatisfy({ $0.name == "file" && $0.value != nil }) else { return nil }
        let fileValues = queryItems.compactMap(\.value)
        guard fileValues.count == operation.requiredFileCount else { return nil }

        let fileURLs = fileValues.compactMap(URL.init(string:))
        guard fileURLs.count == fileValues.count else { return nil }

        self.init(operation: operation, fileURLs: fileURLs)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = operation.rawValue
        components.queryItems = fileURLs.map {
            URLQueryItem(name: "file", value: $0.absoluteString)
        }
        return components.url
    }
}
