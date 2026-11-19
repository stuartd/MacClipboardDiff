import Foundation
import OSLog

nonisolated struct ClipDiffLog: Sendable {
    static let subsystem = "stuartd.clipdiff"
    static let app = ClipDiffLog(category: "App")
    static let updates = ClipDiffLog(category: "Updates")
    static let file: DiagnosticLogFile? = {
        guard Bundle.main.bundleIdentifier == subsystem,
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return DiagnosticLogFile(directory: library.appendingPathComponent("Logs/ClipDiff", isDirectory: true))
    }()

    private let category: String
    private let logger: Logger

    private init(category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    // Callers supply fixed messages with safe metadata such as status codes and validated release tags.
    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        Self.file?.append("[\(category)] \(message)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        Self.file?.append("[\(category)] Error: \(message)")
    }
}

nonisolated final class DiagnosticLogFile: Sendable {
    private let directory: URL
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "stuartd.clipdiff.diagnostic-log", qos: .utility)

    private var current: URL { directory.appendingPathComponent("ClipDiff.log") }
    private var previous: URL { directory.appendingPathComponent("ClipDiff.log.previous") }

    init(directory: URL, maximumBytes: Int = 256 * 1024) {
        self.directory = directory
        self.maximumBytes = maximumBytes
    }

    func append(_ message: String) {
        let data = Data("\(Date().ISO8601Format()) \(message)\n".utf8)
        guard data.count <= maximumBytes else { return }
        queue.async {
            // Keep logging failures independent of clipboard capture and update checks.
            try? self.write(data)
        }
    }

    func read() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try self.read(self.previous) + self.read(self.current)
                })
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    private func write(_ data: Data) throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let size = (try? files.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if size > UInt64(maximumBytes - data.count) {
            if files.fileExists(atPath: previous.path) { try files.removeItem(at: previous) }
            try files.moveItem(at: current, to: previous)
        }
        if !files.fileExists(atPath: current.path) {
            files.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func read(_ url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return ""
        }
        defer { try? handle.close() }
        return String(decoding: try handle.read(upToCount: maximumBytes) ?? Data(), as: UTF8.self)
    }
}
