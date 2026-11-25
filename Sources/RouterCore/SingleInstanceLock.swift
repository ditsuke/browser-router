import Foundation
import Darwin

/// The open descriptor owns the lock. A crash releases it; stale PID text does
/// not prevent a later launch. Never unlink a lock file while it may be held.
public final class SingleInstanceLock {
    private let descriptor: Int32
    public let acquired: Bool

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let acquired: Bool
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            acquired = true
            let data = Data(String(getpid()).utf8)
            guard ftruncate(descriptor, 0) == 0,
                  data.withUnsafeBytes({ Darwin.write(descriptor, $0.baseAddress, $0.count) }) == data.count else {
                let code = errno
                Darwin.close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        } else {
            let code = errno
            guard code == EWOULDBLOCK else {
                Darwin.close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            acquired = false
        }
        self.descriptor = descriptor
        self.acquired = acquired
    }

    public var ownerPID: pid_t? {
        var buffer = [UInt8](repeating: 0, count: 32)
        let count = pread(descriptor, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        return pid_t(String(decoding: buffer.prefix(count), as: UTF8.self))
    }

    deinit { Darwin.close(descriptor) }
}
