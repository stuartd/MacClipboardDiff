import Darwin
import Foundation

/// An advisory lock shared by all builds for this user. Only the owner's PID is
/// stored here; clipboard contents and comparison paths never enter this file.
final class SingleInstanceLock {
    let isOwner: Bool
    private let descriptor: Int32

    convenience init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("ClipDiff", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(url: directory.appendingPathComponent("instance.lock"))
    }

    init(url: URL) throws {
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Self.systemError() }
        do {
            var attributes = stat()
            guard fstat(fd, &attributes) == 0 else { throw Self.systemError() }
            guard attributes.st_mode & S_IFMT == S_IFREG,
                  attributes.st_uid == getuid() else {
                throw POSIXError(.EACCES)
            }

            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                // Ignore stale PIDs: ownership is decided solely by the OS lock.
                let bytes = Array(String(getpid()).utf8)
                guard ftruncate(fd, 0) == 0 else { throw Self.systemError() }
                let count = bytes.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
                guard count == bytes.count else { throw POSIXError(.EIO) }
                isOwner = true
            } else if errno == EWOULDBLOCK {
                isOwner = false
            } else {
                throw Self.systemError()
            }
            descriptor = fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    var ownerProcessIdentifier: pid_t? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = bytes.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, 0) }
        guard count > 0,
              let pid = pid_t(String(decoding: bytes.prefix(count), as: UTF8.self)),
              pid > 0 else { return nil }
        return pid
    }

    deinit {
        // Never unlink the file: another process may already have opened its inode.
        // Closing (including on process death) releases the lock automatically.
        Darwin.close(descriptor)
    }

    private static func systemError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
