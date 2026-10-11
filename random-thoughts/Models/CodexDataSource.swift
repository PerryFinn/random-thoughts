import Foundation

nonisolated enum CodexDiscoveryMode: String, Sendable {
    case automatic
    case manual
}

nonisolated struct CodexDataSourceConfiguration: Equatable, Sendable {
    var mode: CodexDiscoveryMode = .automatic
    var executablePath = ""
    var explicitDirectory = ""
}

nonisolated struct CodexSourceIdentity: Equatable, Sendable {
    let executablePath: String
    let dataDirectory: String
}

nonisolated struct CodexDataSourceSettings: Equatable, Sendable {
    var configuration = CodexDataSourceConfiguration()
    var resolvedDirectory: String?
    var lastSuccessfulCheck: Date?
    var version: CodexVersion?

    var identity: CodexSourceIdentity? {
        guard configuration.executablePath.hasPrefix("/"), !configuration.executablePath.contains("\u{0}"), let resolvedDirectory else { return nil }
        return CodexSourceIdentity(executablePath: configuration.executablePath, dataDirectory: resolvedDirectory)
    }
}

nonisolated struct CodexVersion: Equatable, Sendable, CustomStringConvertible {
    let description: String

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
            return nil
        }
        description = parts.map { String(Int($0)!) }.joined(separator: ".")
    }

    static func fromUserAgent(_ value: String) -> Self? {
        let pattern = #"^(?:random_thoughts|codex_cli_rs|codex-cli|codex)/([0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6})(?:[ +\-]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Self(String(value[range]))
    }
}

nonisolated enum CodexSourceStatus: String, Sendable {
    case unchecked
    case available
    case unavailable

    var title: String {
        switch self {
        case .unchecked: "未检查"
        case .available: "可用"
        case .unavailable: "不可用"
        }
    }
}

nonisolated enum CodexSourceError: String, Error, Sendable, CaseIterable {
    case executableMissing = "executable_missing"
    case invalidExecutable = "invalid_executable"
    case executablePermission = "executable_permission"
    case directoryMissing = "directory_missing"
    case invalidDirectory = "invalid_directory"
    case directoryPermission = "directory_permission"
    case launchFailed = "launch_failed"
    case handshakeFailed = "handshake_failed"
    case readFailed = "read_failed"
    case methodUnsupported = "method_unsupported"
    case parametersUnsupported = "parameters_unsupported"
    case schemaUnsupported = "schema_unsupported"
    case transportInterrupted = "transport_interrupted"
    case timedOut = "timed_out"
    case cancelled

    var message: String {
        switch self {
        case .executableMissing: "找不到已选择的 Codex 入口。请安装 Codex、手选入口或主动重新发现；当前选择已保留。"
        case .invalidExecutable: "Codex 入口须为绝对路径的普通可执行文件。请重新选择入口。"
        case .executablePermission: "无法执行已选择的 Codex 入口。请检查执行权限或重新选择。"
        case .directoryMissing: "已选择的 Codex 数据目录不存在。请修正目录；不会回退到其他来源。"
        case .invalidDirectory: "Codex 数据目录须为现有目录的绝对路径。请重新选择目录。"
        case .directoryPermission: "无法读取已选择的 Codex 数据目录。请检查访问权限；当前选择已保留。"
        case .launchFailed: "无法启动所选 Codex App Server。请检查用户安装的 Codex。"
        case .handshakeFailed: "Codex App Server 握手失败。请更新用户安装的 Codex 后重新检查。"
        case .readFailed: "Codex 未能完成只读检查。请检查所选数据目录的权限后主动重试。"
        case .methodUnsupported: "Codex 缺少必要的稳定读取方法。请更新用户安装的 Codex。"
        case .parametersUnsupported: "Codex 不接受必要的读取参数。请更新用户安装的 Codex。"
        case .schemaUnsupported: "Codex 返回的数据不符合必要读取契约。请更新用户安装的 Codex 后重新检查。"
        case .transportInterrupted: "Codex 检查进程或传输中断。当前选择已保留，可主动重新检查。"
        case .timedOut: "Codex 检查超过 30 秒。检查已结束，可主动重试。"
        case .cancelled: "检查已取消，当前选择及历史诊断保留。可主动重新检查。"
        }
    }

    var isDirectoryError: Bool {
        [.directoryMissing, .invalidDirectory, .directoryPermission].contains(self)
    }

    var isExecutableError: Bool {
        [.executableMissing, .invalidExecutable, .executablePermission, .launchFailed].contains(self)
    }
}

nonisolated struct CodexSourceSelection: Sendable {
    var settings: CodexDataSourceSettings
    var error: CodexSourceError?
}

nonisolated struct CodexCheckEvent: Equatable, Sendable {
    enum Result: String, Sendable { case success, failure, cancelled }
    let result: Result
    let error: CodexSourceError?
    let version: CodexVersion?
}

protocol CodexSourceAccess: Sendable {
    func resolve(_ configuration: CodexDataSourceConfiguration, rediscover: Bool) async -> CodexSourceSelection
    func check(_ source: CodexSourceIdentity) async throws -> CodexVersion?
}
