import Foundation

nonisolated struct GitHubReleaseClient {
    private static let endpoint = URL(string: "https://api.github.com/repos/stuartd/MacClipboardDiff/releases/latest")!
    private static let repository = URL(string: "https://github.com/stuartd/MacClipboardDiff")!
    private static let maximumResponseBytes = 64 * 1024

    enum Failure: Error {
        case invalidResponse
        case httpStatus(Int)
        case responseTooLarge
    }

    private struct Payload: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }

    private nonisolated final class RedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
    }()

    static func releasePage(for version: ReleaseVersion) -> URL {
        repository.appendingPathComponent("releases/tag").appendingPathComponent(version.tag)
    }

    static func fetchLatest() async throws -> ReleaseVersion {
        var request = URLRequest(url: endpoint)
        request.setValue("ClipDiff", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        ClipDiffLog.updates.notice("GET \(endpoint.absoluteString)")

        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        ClipDiffLog.updates.notice("GitHub HTTP status=\(response.statusCode)")
        guard response.statusCode == 200 else { throw Failure.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= maximumResponseBytes else { throw Failure.responseTooLarge }

        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw Failure.responseTooLarge }
            data.append(byte)
        }
        return try decodeRelease(data)
    }

    static func decodeRelease(_ data: Data) throws -> ReleaseVersion {
        let payload = try? JSONDecoder().decode(Payload.self, from: data)
        guard let payload, !payload.draft, !payload.prerelease,
              let version = ReleaseVersion(tag: payload.tagName) else {
            throw Failure.invalidResponse
        }
        return version
    }
}
