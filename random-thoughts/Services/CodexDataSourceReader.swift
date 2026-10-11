import Darwin
import Foundation

nonisolated struct CodexDataSourceReader: CodexSourceAccess {
    private let homeDirectory: URL
    private let environment: [String: String]
    private let homebrewDirectories: [URL]
    private let timeout: TimeInterval
    private let scanLockDirectory: URL
    private let scanLockTimeout: TimeInterval

    init(homeDirectory: URL, environment: [String: String], homebrewDirectories: [URL], timeout: TimeInterval = 30,
         scanLockDirectory: URL, scanLockTimeout: TimeInterval = 30) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.homebrewDirectories = homebrewDirectories
        self.timeout = timeout
        self.scanLockDirectory = scanLockDirectory
        self.scanLockTimeout = scanLockTimeout
    }

    func resolve(_ configuration: CodexDataSourceConfiguration, rediscover: Bool) async -> CodexSourceSelection {
        await Task.detached(priority: .userInitiated) {
            var configuration = configuration
            if configuration.mode == .automatic, configuration.executablePath.isEmpty || rediscover {
                let candidates = [homeDirectory.appendingPathComponent(".local/bin/codex")]
                    + (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
                        .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }
                    + homebrewDirectories.map { $0.appendingPathComponent("codex") }
                configuration.executablePath = candidates.first { Self.executableError($0.path) == nil }?.path ?? ""
            }
            let entryError = Self.executableError(configuration.executablePath)
            let directoryPath = configuration.explicitDirectory.isEmpty
                ? environment["CODEX_HOME"] ?? homeDirectory.appendingPathComponent(".codex").path
                : configuration.explicitDirectory
            let directoryError = Self.directoryError(directoryPath)
            let resolvedDirectory: String?
            if directoryError == nil, let resolved = realpath(directoryPath, nil) {
                resolvedDirectory = String(cString: resolved)
                free(resolved)
            } else { resolvedDirectory = nil }
            return CodexSourceSelection(
                settings: CodexDataSourceSettings(
                    configuration: configuration,
                    resolvedDirectory: resolvedDirectory
                ), error: entryError ?? directoryError ?? (resolvedDirectory == nil ? .directoryPermission : nil)
            )
        }.value
    }

    func check(_ source: CodexSourceIdentity) async throws -> CodexVersion? {
        let operation = CodexStdioSession(source: source, environment: environment, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try operation.check() }.value
        } onCancel: {
            operation.cancel(.cancelled)
        }
    }

    func scan(_ source: CodexSourceIdentity, day: ReportDay,
              progress: @escaping @Sendable (CodexScanActivity) -> Void) async throws -> CodexSessionScan {
        if let error = Self.executableError(source.executablePath) ?? Self.directoryError(source.dataDirectory) { throw error }
        let operation = CodexScanOperation(source: source, environment: environment, timeout: timeout,
                                           lockDirectory: scanLockDirectory, lockTimeout: scanLockTimeout)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try operation.run(day: day, progress: progress) }.value
        } onCancel: {
            operation.cancel()
        }
    }

    private static func executableError(_ path: String) -> CodexSourceError? {
        if path.isEmpty { return .executableMissing }
        guard path.hasPrefix("/"), !path.contains("\u{0}") else { return .invalidExecutable }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path.lowercased()
        guard !resolved.contains(".app/contents/"), !path.lowercased().contains(".app/contents/") else { return .invalidExecutable }
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == ENOENT ? .executableMissing : .executablePermission }
        guard info.st_mode & S_IFMT == S_IFREG else { return .invalidExecutable }
        return Darwin.access(path, X_OK) == 0 ? nil : .executablePermission
    }

    private static func directoryError(_ path: String) -> CodexSourceError? {
        guard path.hasPrefix("/"), !path.contains("\u{0}") else { return .invalidDirectory }
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == ENOENT ? .directoryMissing : .directoryPermission }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .invalidDirectory }
        return Darwin.access(path, R_OK | X_OK) == 0 ? nil : .directoryPermission
    }
}
