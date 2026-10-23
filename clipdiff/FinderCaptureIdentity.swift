import CryptoKit
import Foundation

/// Only a session-salted path fingerprint crosses into the Finder extension.
/// Source paths and contents stay with the app's in-memory history.
nonisolated struct FinderCaptureIdentity: Codable, Equatable, Sendable {
    static let requestNotification = Notification.Name("stuartd.clipdiff.request-capture-identity")
    static let changedNotification = Notification.Name("stuartd.clipdiff.capture-identity-changed")

    let processIdentifier: Int32
    let sessionID: UUID
    let revision: UInt64
    private let pathFingerprint: String?

    init(
        sourceFilePath: String?,
        processIdentifier: Int32,
        sessionID: UUID,
        revision: UInt64
    ) {
        self.processIdentifier = processIdentifier
        self.sessionID = sessionID
        self.revision = revision
        pathFingerprint = sourceFilePath.flatMap { path in
            guard NSString(string: path).isAbsolutePath else { return nil }
            return Self.fingerprint(URL(fileURLWithPath: path), sessionID: sessionID)
        }
    }

    init?(notificationObject: Any?) {
        guard let string = notificationObject as? String,
              let data = string.data(using: .utf8),
              let identity = try? JSONDecoder().decode(Self.self, from: data),
              identity.processIdentifier > 0 else { return nil }
        if let fingerprint = identity.pathFingerprint {
            guard fingerprint.utf8.count == 64,
                  fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                return nil
            }
        }
        self = identity
    }

    var notificationObject: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func matches(_ fileURL: URL) -> Bool {
        guard fileURL.isFileURL, let pathFingerprint else { return false }
        return pathFingerprint == Self.fingerprint(fileURL, sessionID: sessionID)
    }

    static func isSamePath(_ fileURL: URL, sourceFilePath: String?) -> Bool {
        guard fileURL.isFileURL, let sourceFilePath,
              NSString(string: sourceFilePath).isAbsolutePath else { return false }
        return fileURL.standardizedFileURL.path
            == URL(fileURLWithPath: sourceFilePath).standardizedFileURL.path
    }

    private static func fingerprint(_ fileURL: URL, sessionID: UUID) -> String {
        let path = fileURL.standardizedFileURL.path.precomposedStringWithCanonicalMapping
        let data = Data((sessionID.uuidString + "\0" + path).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
