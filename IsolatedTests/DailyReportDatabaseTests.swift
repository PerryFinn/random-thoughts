import Foundation
import SQLite3
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportDatabaseTests {
    @Test func sourceAndDiagnosticsCommitTogetherReopenAndIgnoreOldIdentity() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var database: DailyReportDatabase? = DailyReportDatabase(directory: environment.directory)
        let initial = try await #require(database).load()
        let first = CodexDataSourceSettings(configuration: CodexDataSourceConfiguration(mode: .automatic, executablePath: "/synthetic/stable", explicitDirectory: ""),
                                            resolvedDirectory: "/synthetic/first")
        let second = CodexDataSourceSettings(configuration: CodexDataSourceConfiguration(mode: .manual, executablePath: "/synthetic/replaced", explicitDirectory: "/synthetic/alias"),
                                             resolvedDirectory: "/synthetic/second")
        try await #require(database).saveCodexSource(first)
        try await #require(database).saveCodexDiagnostic(identity: try #require(first.identity), checkedAt: environment.clock.now, version: CodexVersion("9.8.7"))
        let success = try await #require(database).load().codexSource
        #expect(success.configuration == first.configuration)
        #expect(success.lastSuccessfulCheck == environment.clock.now)
        #expect(success.version?.description == "9.8.7")
        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(environment.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM codex_source", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: ReportStorageError.writeFailed) { try await #require(database).saveCodexSource(second) }
        #expect(try await #require(database).load().codexSource == success)
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        try await #require(database).saveCodexSource(second)
        try await #require(database).saveCodexDiagnostic(identity: try #require(first.identity), checkedAt: environment.clock.now, version: CodexVersion("1.2.3"))
        try await #require(database).close()
        database = nil
        let restored = try await DailyReportDatabase(directory: environment.directory).load()
        #expect(restored.codexSource == second)
        #expect(restored.generalSettings == initial.generalSettings)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)) == ["reports.sqlite", "storage.lock"])
    }

    @Test(arguments: ["source-old-schema", "source-bad-mode", "source-bad-version", "source-missing", "source-bad-history", "source-bad-schema"])
    func sourceStorageFaultsRejectWithoutChangingTheOriginalDatabase(_ scenario: String) throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 0)
    }

    @Test(arguments: ["Etc/GMT+8", "Etc/GMT-14", "CET", "EET", "MET", "WET", "CST6CDT", "PST8PDT"])
    func validFixedIanaSettingsAndReportsReopenWithTheirOriginalIdentity(_ identifier: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var database: DailyReportDatabase? = DailyReportDatabase(directory: environment.directory)
        var settings = try await #require(database).load().generalSettings
        settings.timeZoneMode = .fixed
        settings.fixedTimeZoneIdentifier = identifier
        try await #require(database).saveGeneralSettings(settings)
        let report = SavedDailyReport(
            day: ReportDay(date: environment.clock.now, timeZone: try #require(TimeZone(identifier: identifier))),
            markdown: "时区原身份 IANA_REPORT_24", savedAt: environment.clock.now, lastEditedAt: nil
        )
        try await #require(database).save(report)
        try await #require(database).close()
        database = nil
        let restored = try await DailyReportDatabase(directory: environment.directory).load()
        #expect(restored.generalSettings == settings)
        #expect(restored.reports == [report])
    }

    @Test(arguments: ["old-schema", "settings-bad-mode", "settings-bad-language", "settings-bad-lookback", "settings-missing", "settings-invalid-timezone"])
    func savedSettingsFaultsPreserveTheOriginalDatabase(_ scenario: String) throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 0)
    }

    @Test func sqliteCommitsGeneralSettingsTogetherAndRollsBackRealCommitFailure() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var database: DailyReportDatabase? = DailyReportDatabase(directory: environment.directory)
        let initial = try await #require(database).load()
        let report = SavedDailyReport(
            day: ReportDay(date: environment.clock.now, timeZone: TimeZone(identifier: "Etc/UTC")!),
            markdown: "历史原文 HISTORY_BODY_24", savedAt: environment.clock.now, lastEditedAt: nil
        )
        try await #require(database).save(report)
        var revised = initial.generalSettings
        revised.timeZoneMode = .fixed
        revised.fixedTimeZoneIdentifier = "America/New_York"
        revised.outputLanguage = .english
        revised.generationPreferences = "  偏好 SQLITE_PREFERENCES_24\u{0}é👩🏽‍💻\n"
        revised.historyLookbackDays = 7

        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(environment.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM general_settings", nil, nil, nil) == SQLITE_OK)
        do {
            try await #require(database).saveGeneralSettings(revised)
            Issue.record("读事务应阻止本次真实提交")
        } catch ReportStorageError.writeFailed { }
        let afterFailure = try await #require(database).load()
        #expect(afterFailure.generalSettings == initial.generalSettings)
        #expect(afterFailure.reports == [report])
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        try await #require(database).saveGeneralSettings(revised)
        try await #require(database).close()
        database = nil
        let restored = try await DailyReportDatabase(directory: environment.directory).load()
        #expect(restored.generalSettings == revised)
        #expect(restored.generalSettings.generationPreferences.utf8.elementsEqual(revised.generationPreferences.utf8))
        #expect(restored.reports == [report])
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)) == ["reports.sqlite", "storage.lock"])
    }

    @Test func directoryLockExcludesAnotherProcessAndReleasesWithTheOwner() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var owner: DailyReportDatabase? = DailyReportDatabase(directory: environment.directory)
        _ = try await owner?.load()
        #expect(try runStorageProbe("open", directory: environment.directory) == 73)
        await owner?.close()
        owner = nil
        #expect(try runStorageProbe("open", directory: environment.directory) == 0)
    }

    @Test(arguments: ["commit-failure", "unsupported", "bad-field", "missing-with-journal", "missing-with-reset", "existing-with-reset", "permissions", "bad-schema", "duplicate-day"])
    func storageFaultsPreserveDataInDedicatedProcesses(_ scenario: String) throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 0)
    }

    @Test func sqlitePersistsOnlyExplicitRawReportsAndNormalSize() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let empty = try await database.load()
        #expect(empty.reports.isEmpty)
        let day = ReportDay(date: environment.clock.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let raw = " 合成 RAW_STORAGE_23\u{0}é\n\n尾行  \n"
        let report = SavedDailyReport(day: day, markdown: raw, savedAt: environment.clock.now, lastEditedAt: nil)
        try await database.save(report)
        try await database.saveWindowSize(CGSize(width: 1234, height: 789))
        let loaded = try await database.load()
        #expect(loaded.reports == [report])
        #expect(loaded.reports.first?.markdown.utf8.elementsEqual(raw.utf8) == true)
        #expect(loaded.windowSize == CGSize(width: 1234, height: 789))
        let attributes = try FileManager.default.attributesOfItem(atPath: environment.databaseURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: environment.directory.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let files = try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)
        #expect(Set(files) == ["reports.sqlite", "storage.lock"])
    }
}
