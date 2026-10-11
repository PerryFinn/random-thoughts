import CryptoKit
import Darwin
import Foundation

nonisolated enum CodexScanLock {
    static func withLock<Result>(source: CodexSourceIdentity, directory: URL, timeout: TimeInterval,
                                checkCancellation: () throws -> Void, onWait: () -> Void,
                                operation: () throws -> Result) throws -> Result {
        try checkCancellation()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw CodexSourceError.scanLockUnavailable }
        let key = Data((source.executablePath + "\u{0}" + source.dataDirectory).utf8)
        let name = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        let path = directory.appendingPathComponent(name).path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CodexSourceError.scanLockUnavailable }
        defer { Darwin.close(descriptor) }
        let deadline = DispatchTime.now() + timeout
        var reportedWait = false
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else { throw CodexSourceError.scanLockUnavailable }
            try checkCancellation()
            guard DispatchTime.now() < deadline else { throw CodexSourceError.scanLockTimedOut }
            if !reportedWait { onWait(); reportedWait = true }
            // Runtime lock polling; tests wait for the observable contention event, not a sleep.
            usleep(10_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        try checkCancellation()
        return try operation()
    }
}
