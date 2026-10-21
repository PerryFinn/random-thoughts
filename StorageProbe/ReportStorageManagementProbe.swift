import Darwin
import Foundation
import SQLite3
@testable import random_thoughts

enum ReportStorageManagementProbe {
    static func run(_ scenario: String, directory: URL) async throws {
        let url = directory.appendingPathComponent("reports.sqlite")
        let crashPhase: ReportResetPhase? = switch scenario {
        case "management-reset-intent": .intentRecorded
        case "management-reset-removed": .filesRemoved
        case "management-reset-initialized": .databaseInitialized
        default: nil
        }
        let store = DailyReportDatabase(directory: directory, resetProgress: { phase in
            if phase == crashPhase { _exit(86) }
        })
        if scenario == "management-reset-occupied" { _ = try await store.reset(); throw ProbeError.failed }
        _ = try await store.load()
        let report = SavedDailyReport(day: try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Asia/Shanghai"),
            markdown: "SYNTHETIC_ORIGINAL_33\n", savedAt: Date(timeIntervalSince1970: 100), lastEditedAt: nil)
        try await store.save(report)
        if crashPhase != nil { _ = try await store.reset(); throw ProbeError.failed }
        await store.close()
        var raw: OpaquePointer?
        guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw ProbeError.failed }
        defer { sqlite3_close(raw) }
        if scenario == "management-journal-crash" || scenario == "management-migration-crash" {
            if scenario == "management-migration-crash" { try sql("PRAGMA user_version=4", raw) }
            try sql("PRAGMA cache_size=1; PRAGMA synchronous=EXTRA; BEGIN IMMEDIATE", raw)
            try sql("UPDATE reports SET markdown='" + String(repeating: "SYNTHETIC_UNCOMMITTED_33", count: 50_000) + "'; PRAGMA user_version=5", raw)
            guard sqlite3_db_cacheflush(raw) == SQLITE_OK else { throw ProbeError.failed }
            _exit(86)
        }
        guard scenario == "management-migration-commit" else { throw ProbeError.failed }
        try sql("PRAGMA user_version=4; BEGIN; SELECT * FROM reports", raw)
        let before = try Data(contentsOf: url)
        let upgrading = DailyReportDatabase(directory: directory)
        do { _ = try await upgrading.load(); throw ProbeError.failed }
        catch ReportStorageError.migrationFailed { }
        guard try Data(contentsOf: url) == before else { throw ProbeError.failed }
        await upgrading.close()
        try sql("ROLLBACK", raw)
        let restored = DailyReportDatabase(directory: directory)
        guard try await restored.load().reports == [report] else { throw ProbeError.failed }
        await restored.close()
    }

    private static func sql(_ text: String, _ database: OpaquePointer?) throws {
        guard sqlite3_exec(database, text, nil, nil, nil) == SQLITE_OK else { throw ProbeError.failed }
    }
    private enum ProbeError: Error { case failed }
}
