import Darwin
import Foundation
import SQLite3
@testable import random_thoughts

@main
struct ReportStorageProbe {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 3,
              let root = ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"],
              arguments[2].hasPrefix(root + "/") else { exit(2) }
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        do {
            try await run(arguments[1], directory: directory)
            exit(0)
        } catch ReportStorageError.occupied {
            exit(73)
        } catch {
            // Never print raw database errors, paths or content, including test failures.
            exit(1)
        }
    }

    private static func run(_ scenario: String, directory: URL) async throws {
        if scenario.hasPrefix("management-") {
            try await ReportStorageManagementProbe.run(scenario, directory: directory)
            return
        }
        if scenario == "hold-scan-lock" {
            guard let executable = ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"] else { throw ProbeError.failed }
            try CodexScanLock.withLock(source: CodexSourceIdentity(executablePath: executable, dataDirectory: directory.path),
                                      directory: directory.appendingPathComponent("locks"), timeout: 30,
                                      checkCancellation: {}, onWait: {}) {
                let ready = try FileHandle(forWritingTo: directory.appendingPathComponent("lock-ready"))
                try ready.write(contentsOf: Data([1]))
                try ready.close()
                guard try FileHandle.standardInput.read(upToCount: 1)?.count == 1 else { throw ProbeError.failed }
            }
            return
        }
        let url = directory.appendingPathComponent("reports.sqlite")
        if scenario == "open" {
            _ = try await DailyReportDatabase(directory: directory).load()
            return
        }
        if scenario == "missing-with-journal" || scenario == "missing-with-reset" {
            let name = scenario == "missing-with-journal" ? "reports.sqlite-journal" : "reset-intent"
            try Data("SYNTHETIC_RECOVERY_23".utf8).write(to: directory.appendingPathComponent(name))
            try await expectRejection(.recoveryRequired, directory: directory)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw ProbeError.failed }
            return
        }
        var database: DailyReportDatabase? = DailyReportDatabase(directory: directory)
        _ = try await database!.load()
        let report = SavedDailyReport(
            day: ReportDay(date: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "Etc/UTC")!),
            markdown: "SYNTHETIC_ORIGINAL_23\n", savedAt: Date(timeIntervalSince1970: 100), lastEditedAt: nil
        )
        try await database!.save(report)
        if scenario == "commit-failure" {
            var reader: OpaquePointer?
            guard sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw ProbeError.failed }
            defer { sqlite3_close(reader) }
            guard sqlite3_exec(reader, "BEGIN; SELECT * FROM reports", nil, nil, nil) == SQLITE_OK else { throw ProbeError.failed }
            let revised = SavedDailyReport(day: report.day, markdown: "SYNTHETIC_NEW_23", savedAt: Date(timeIntervalSince1970: 200), lastEditedAt: nil)
            do {
                try await database!.save(revised)
                throw ProbeError.failed
            } catch ReportStorageError.writeFailed { }
            guard try await database!.load().reports == [report] else { throw ProbeError.failed }
            guard sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK else { throw ProbeError.failed }
            try await database!.save(revised)
            guard try await database!.load().reports == [revised] else { throw ProbeError.failed }
            return
        }
        await database?.close()
        database = nil
        let expected: ReportStorageError
        switch scenario {
        case "unsupported":
            try execute("PRAGMA user_version=99", at: url)
            expected = .unsupportedVersion
        case "bad-field":
            try execute("UPDATE reports SET calendar_date='2026-02-30'", at: url)
            expected = .invalidData
        case "bad-schema":
            try execute("ALTER TABLE reports ADD COLUMN unknown TEXT", at: url)
            expected = .invalidData
        case "duplicate-day":
            try execute("""
                ALTER TABLE reports RENAME TO original_reports;
                CREATE TABLE reports (
                    calendar_date TEXT NOT NULL, time_zone TEXT NOT NULL, markdown TEXT NOT NULL,
                    saved_at REAL NOT NULL, last_edited_at REAL
                ) STRICT;
                INSERT INTO reports SELECT * FROM original_reports;
                INSERT INTO reports SELECT * FROM original_reports;
                """, at: url)
            expected = .invalidData
        case "old-schema":
            try execute("PRAGMA user_version=1", at: url)
            expected = .invalidData
        case "source-old-schema":
            try execute("PRAGMA user_version=2", at: url)
            expected = .invalidData
        case "ai-old-schema":
            try execute("PRAGMA user_version=3", at: url)
            expected = .invalidData
        case "ai-missing-row":
            try execute("DELETE FROM ai_services WHERE protocol='responses'", at: url)
            expected = .invalidData
        case "ai-unknown-protocol":
            try execute("UPDATE ai_services SET protocol='unknown' WHERE protocol='responses'", at: url)
            expected = .invalidData
        case "ai-bad-record":
            try execute("UPDATE ai_services SET record='{}' WHERE protocol='responses'", at: url)
            expected = .invalidData
        case "ai-bad-budget":
            try execute("UPDATE ai_services SET record=json_set(record,'$.configuration.totalBudget',0) WHERE protocol='responses'", at: url)
            expected = .invalidData
        case "ai-bad-schema":
            try execute("ALTER TABLE ai_services ADD COLUMN raw_key TEXT", at: url)
            expected = .invalidData
        case "ai-missing-selection":
            try execute("DELETE FROM ai_selection", at: url)
            expected = .invalidData
        case "source-bad-mode":
            try execute("UPDATE codex_source SET mode='unknown'", at: url)
            expected = .invalidData
        case "source-bad-version":
            try execute("UPDATE codex_source SET version='RAW_VERSION_SECRET_25'", at: url)
            expected = .invalidData
        case "source-missing":
            try execute("DELETE FROM codex_source", at: url)
            expected = .invalidData
        case "source-bad-history":
            try execute("UPDATE codex_source SET last_successful_check=100", at: url)
            expected = .invalidData
        case "source-bad-schema":
            try execute("ALTER TABLE codex_source ADD COLUMN raw_response TEXT", at: url)
            expected = .invalidData
        case "settings-bad-mode":
            try execute("UPDATE general_settings SET time_zone_mode='unknown'", at: url)
            expected = .invalidData
        case "settings-bad-language":
            try execute("UPDATE general_settings SET output_language='unknown'", at: url)
            expected = .invalidData
        case "settings-bad-lookback":
            try execute("UPDATE general_settings SET history_lookback_days=8", at: url)
            expected = .invalidData
        case "settings-missing":
            try execute("DELETE FROM general_settings", at: url)
            expected = .invalidData
        case "settings-invalid-timezone":
            try execute("UPDATE general_settings SET time_zone_mode='fixed',fixed_time_zone='INVALID/IANA_24'", at: url)
            let original = try Data(contentsOf: url)
            let loaded = try await DailyReportDatabase(directory: directory).load()
            guard loaded.generalSettings.fixedTimeZoneIdentifier == "INVALID/IANA_24",
                  loaded.generalSettings.timeZoneMode == .fixed,
                  loaded.generalSettings.effectiveTimeZone(macTimeZone: TimeZone(identifier: "Asia/Shanghai")!) == nil,
                  loaded.reports == [report], try Data(contentsOf: url) == original else { throw ProbeError.failed }
            return
        case "permissions":
            guard chmod(url.path, 0o400) == 0 else { throw ProbeError.failed }
            expected = .unavailable
        case "existing-with-reset":
            try Data("SYNTHETIC_RESET_23".utf8).write(to: directory.appendingPathComponent("reset-intent"))
            expected = .recoveryRequired
        default: throw ProbeError.failed
        }
        let original = try Data(contentsOf: url)
        try await expectRejection(expected, directory: directory)
        guard try Data(contentsOf: url) == original else { throw ProbeError.failed }
    }

    private static func expectRejection(_ expected: ReportStorageError, directory: URL) async throws {
        do {
            _ = try await DailyReportDatabase(directory: directory).load()
            throw ProbeError.failed
        } catch let error as ReportStorageError {
            guard error == expected else { throw ProbeError.failed }
        }
    }

    private static func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw ProbeError.failed }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw ProbeError.failed }
    }

    private enum ProbeError: Error { case failed }
}
