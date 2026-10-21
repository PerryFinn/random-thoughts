import Foundation

nonisolated struct ReportDay: Hashable, Sendable, Identifiable {
    let calendarDate: String
    let timeZoneIdentifier: String

    var id: Self { self }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier)! }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    var start: Date {
        let parts = calendarDate.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }
    var interval: DateInterval {
        calendar.dateInterval(of: .day, for: start)!
    }

    init(date: Date, timeZone: TimeZone) {
        timeZoneIdentifier = timeZone.identifier == "GMT" ? "Etc/UTC" : timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        calendarDate = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    init(calendarDate: String, timeZoneIdentifier: String) throws {
        guard let timeZone = ReportTimeZone.resolve(timeZoneIdentifier),
              calendarDate.utf8.count == 10 else { throw ReportStorageError.invalidData }
        let parts = calendarDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { throw ReportStorageError.invalidData }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              Self(date: date, timeZone: timeZone).calendarDate == calendarDate else { throw ReportStorageError.invalidData }
        self.calendarDate = calendarDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated struct SavedDailyReport: Equatable, Sendable {
    let day: ReportDay
    let markdown: String
    let savedAt: Date
    let lastEditedAt: Date?
}

nonisolated struct ReportStorageSnapshot: Sendable {
    var reports: [SavedDailyReport]
    var windowSize: CGSize?
    var generalSettings: DailyReportGeneralSettings
    var codexSource: CodexDataSourceSettings
    var aiServices: AIServiceSettings
}

nonisolated struct ReportContentCounts: Equatable, Sendable {
    let saved: Int
    let drafts: Int
    let snapshots: Int
}

protocol DailyReportStorage: Actor {
    var dataDirectory: URL? { get async }
    func load() async throws -> ReportStorageSnapshot
    func save(_ report: SavedDailyReport) async throws
    func deleteReports(day: ReportDay?) async throws
    func reset() async throws -> ReportStorageSnapshot
    func saveWindowSize(_ size: CGSize) async throws
    func saveGeneralSettings(_ settings: DailyReportGeneralSettings) async throws
    func saveCodexSource(_ settings: CodexDataSourceSettings) async throws
    func saveCodexDiagnostic(identity: CodexSourceIdentity, checkedAt: Date, version: CodexVersion?) async throws
    func saveAIService(_ service: SavedAIService) async throws
    func saveAIValidation(_ proof: AIServiceValidation, matching baseline: AIValidationBaseline) async throws -> Bool
    func saveCurrentAIService(_ service: AIServiceType) async throws
}

nonisolated enum ReportStorageError: Error, Sendable {
    case occupied
    case unavailable
    case invalidData
    case unsupportedVersion
    case recoveryRequired
    case writeFailed
    case migrationFailed
    case resetIncomplete

    var message: String {
        switch self {
        case .occupied: "日报存储正被另一个应用实例使用。请退出该实例后重新打开日报。"
        case .unavailable: "无法打开日报存储。请检查本机数据目录的访问权限后重新打开日报。"
        case .invalidData: "日报数据或格式无法读取。原数据已保留，请使用兼容应用检查。"
        case .unsupportedVersion: "此日报数据库版本不受支持。请使用兼容版本打开，原数据已保留。"
        case .recoveryRequired: "日报目录包含待恢复状态，已停止创建或写入数据库。请先完成恢复。"
        case .writeFailed: "本地保存失败，已保存日报未改变。可以重试保存或复制 Markdown。"
        case .migrationFailed: "日报格式升级未能提交，旧数据已保留。请检查权限、磁盘空间或使用兼容版本；依赖操作已停止。"
        case .resetIncomplete: "已确认的日报重置尚未完成，旧数据可能已部分清除。依赖操作已停止；请修复权限或磁盘空间后继续重置。"
        }
    }
}

nonisolated struct ReportConfirmation: Identifiable, Sendable {
    enum Kind: Sendable {
        case overwrite(ReportDay)
        case discard(ReportDay)
        case deleteReport(ReportDay, window: AppWindowKind)
        case clearReports
        case resetData
        case close(UUID)
        case quit
        case settings(ReportSettingsContinuation)
        case codexSettings(ReportSettingsContinuation)
        case aiSettings(ReportSettingsContinuation)
        case deleteAICredential(AIServiceType, version: Int64, revision: UInt64)
        case unknownSources
        case generate(ReportDay)
        case generationPlan(ReportDay)
        case validationExit(ReportSettingsContinuation)
    }

    let id = UUID()
    let kind: Kind
    let previousMarkdown: String?
    let markdown: String?
    let draftDays: [ReportDay]
    var settings: DailyReportGeneralSettings? = nil
    var codexConfiguration: CodexDataSourceConfiguration? = nil
    var aiEdit: AIServiceEdit? = nil
    var oldTimeZoneIdentifier: String? = nil
    var newTimeZoneIdentifier: String? = nil
    var generationContext: ReportGenerationContext? = nil
    var generationScale: ReportGenerationScale? = nil
    var isGenerating = false
    var contentCounts: ReportContentCounts? = nil
    var savedDays: [ReportDay] = []

    var windowKind: AppWindowKind {
        switch kind {
        case .deleteReport(_, let window): window
        case .settings, .codexSettings, .aiSettings, .deleteAICredential, .validationExit, .clearReports, .resetData: .settings
        default: .report
        }
    }
}
