import Foundation

nonisolated enum ReportTimeZoneMode: String, CaseIterable, Sendable {
    case followMac
    case fixed
}

nonisolated enum ReportOutputLanguage: String, CaseIterable, Sendable {
    case chinese
    case english
}

nonisolated enum ReportTimeZone {
    // IANA names omitted by Foundation's geographic search list; these are identifiers, not arbitrary abbreviations.
    private static let flatIanaIdentifiers = [
        "CET", "CST6CDT", "Cuba", "EET", "EST", "EST5EDT", "Egypt", "Eire", "GB", "GB-Eire",
        "GMT", "GMT+0", "GMT-0", "GMT0", "Greenwich", "HST", "Hongkong", "Iceland", "Iran", "Israel",
        "Jamaica", "Japan", "Kwajalein", "Libya", "MET", "MST", "MST7MDT", "NZ", "NZ-CHAT", "Navajo",
        "PRC", "PST8PDT", "Poland", "Portugal", "ROC", "ROK", "Singapore", "Turkey", "UCT", "UTC",
        "Universal", "W-SU", "WET", "Zulu"
    ]

    static let searchableIdentifiers = Array(Set(
        TimeZone.knownTimeZoneIdentifiers + flatIanaIdentifiers + ["Etc/UTC", "Etc/GMT"]
            + (1...14).map { "Etc/GMT-\($0)" } + (1...12).map { "Etc/GMT+\($0)" }
    )).filter { TimeZone(identifier: $0) != nil }.sorted()

    static func resolve(_ identifier: String) -> TimeZone? {
        guard identifier.contains("/") || flatIanaIdentifiers.contains(identifier) else { return nil }
        return TimeZone(identifier: identifier)
    }
}

nonisolated struct DailyReportGeneralSettings: Equatable, Sendable {
    var timeZoneMode: ReportTimeZoneMode = .followMac
    var fixedTimeZoneIdentifier = "Etc/UTC"
    var outputLanguage: ReportOutputLanguage = .chinese
    var generationPreferences = ""
    var historyLookbackDays = 1

    func effectiveTimeZone(macTimeZone: TimeZone) -> TimeZone? {
        switch timeZoneMode {
        case .followMac: return macTimeZone
        case .fixed: return ReportTimeZone.resolve(fixedTimeZoneIdentifier)
        }
    }

    var validationError: ReportSettingsValidationError? {
        if timeZoneMode == .fixed, effectiveTimeZone(macTimeZone: .gmt) == nil { return .invalidTimeZone }
        if !(0...7).contains(historyLookbackDays) { return .invalidLookback }
        return nil
    }
}

nonisolated enum ReportSettingsValidationError: Hashable, Sendable {
    case invalidTimeZone
    case invalidLookback

    var message: String {
        switch self {
        case .invalidTimeZone: "请选择有效的 IANA 报告时区。原时区仍保留，扫描和生成需要先修正此设置。"
        case .invalidLookback: "历史回看须为 0–7 个日历日。"
        }
    }
}

nonisolated enum ReportSettingsPage: String, CaseIterable, Sendable {
    case intelligence
    case proximityUnlock
    case general
    case dataSource
    case aiServices
    case contentManagement
}

nonisolated enum ReportSettingsContinuation: Sendable {
    case stay
    case page(ReportSettingsPage)
    case close(UUID)
    case quit
}

nonisolated enum ReportContextEffect: Equatable, Sendable {
    case codexSourceChanged(revision: UInt64)
    case cancelTimeZoneTasks(String, revision: UInt64)
    case rescan(ReportDay, revision: UInt64)
}
