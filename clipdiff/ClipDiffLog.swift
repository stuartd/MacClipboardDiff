import OSLog

nonisolated enum ClipDiffLog {
    static let app = Logger(subsystem: "stuartd.clipdiff", category: "App")
    static let updates = Logger(subsystem: "stuartd.clipdiff", category: "Updates")
}
