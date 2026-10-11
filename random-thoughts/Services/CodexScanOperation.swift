import Foundation

// The worker owns protocol I/O; this lock only protects cancellation and the currently owned child.
nonisolated final class CodexScanOperation: @unchecked Sendable {
    private let source: CodexSourceIdentity
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let lockDirectory: URL
    private let lockTimeout: TimeInterval
    private let lock = NSLock()
    private var isCancelled = false
    private var session: CodexStdioSession?

    init(source: CodexSourceIdentity, environment: [String: String], timeout: TimeInterval,
         lockDirectory: URL, lockTimeout: TimeInterval) {
        self.source = source
        self.environment = environment
        self.timeout = timeout
        self.lockDirectory = lockDirectory
        self.lockTimeout = lockTimeout
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        session?.cancel(.cancelled)
    }

    func run(day: ReportDay, progress: @escaping @Sendable (CodexScanActivity) -> Void) throws -> CodexSessionScan {
        try CodexScanLock.withLock(source: source, directory: lockDirectory, timeout: lockTimeout,
                                  checkCancellation: checkCancellation, onWait: { progress(.waitingForSource) }) {
            progress(.reading)
            return try read(day: day)
        }
    }

    private func read(day: ReportDay) throws -> CodexSessionScan {
        for attempt in 0...1 {
            let session = CodexStdioSession(source: source, environment: environment, timeout: timeout)
            lock.lock()
            if isCancelled { lock.unlock(); throw CodexSourceError.cancelled }
            self.session = session
            lock.unlock()
            do { return try session.scan(day: day) }
            catch let error as CodexSourceError {
                try checkCancellation()
                guard attempt == 0, error == .transportInterrupted || error == .timedOut else { throw error }
            }
        }
        throw CodexSourceError.transportInterrupted
    }

    private func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled { throw CodexSourceError.cancelled }
    }
}
