import Darwin
import Foundation

nonisolated enum ReportResetPhase: Sendable { case intentRecorded, filesRemoved, databaseInitialized }

// Kept by the storage actor even if opening or migration fails. Never unlink a held lock.
nonisolated final class ReportStorageDirectory {
    private var descriptor: Int32 = -1
    private let directory: URL
    private static let resetIntent = Data("DailyReports.reset.v1\n".utf8)
    private var marker: URL { directory.appendingPathComponent("reset-intent") }

    init(_ directory: URL) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { throw ReportStorageError.unavailable }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), chmod(directory.path, 0o700) == 0 else { throw ReportStorageError.unavailable }
        descriptor = Darwin.open(directory.appendingPathComponent("storage.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else { throw ReportStorageError.unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw errno == EWOULDBLOCK ? ReportStorageError.occupied : .unavailable
        }
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    func hasConfirmedReset() throws -> Bool {
        guard try Self.exists(marker) else { return false }
        var info = stat()
        guard lstat(marker.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size == Self.resetIntent.count,
              (try? Data(contentsOf: marker)) == Self.resetIntent else { throw ReportStorageError.recoveryRequired }
        return true
    }

    func recordResetIntent() throws {
        if (try? hasConfirmedReset()) == true { return }
        let file = Darwin.open(marker.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw ReportStorageError.resetIncomplete }
        defer { Darwin.close(file) }
        let count = Self.resetIntent.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) }
        guard count == Self.resetIntent.count, fchmod(file, 0o600) == 0,
              fsync(file) == 0 else { throw ReportStorageError.resetIncomplete }
        try synchronize()
    }

    func removeDatabaseFiles() throws {
        for name in ["reports.sqlite", "reports.sqlite-journal", "reports.sqlite-wal", "reports.sqlite-shm"] {
            let url = directory.appendingPathComponent(name)
            if try Self.exists(url) {
                do { try FileManager.default.removeItem(at: url) }
                catch { throw ReportStorageError.resetIncomplete }
            }
        }
        try synchronize()
    }

    func completeReset() throws {
        do { try FileManager.default.removeItem(at: marker) }
        catch { throw ReportStorageError.resetIncomplete }
        try synchronize()
    }

    private func synchronize() throws {
        let file = Darwin.open(directory.path, O_RDONLY | O_CLOEXEC)
        guard file >= 0 else { throw ReportStorageError.resetIncomplete }
        defer { Darwin.close(file) }
        guard fsync(file) == 0 else { throw ReportStorageError.resetIncomplete }
    }

    static func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        guard errno == ENOENT else { throw ReportStorageError.unavailable }
        return false
    }
}
