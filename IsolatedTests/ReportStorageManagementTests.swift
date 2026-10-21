import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import random_thoughts

@MainActor
struct ReportStorageManagementTests {
    @Test(arguments: ["format", "key", "authentication"])
    func migrationPreservesUnreadableCredentialsAndOnlyBlocksTheirService(_ fault: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let initial = try await database.load()
        let good = try legacyCredential("SYNTHETIC_READABLE_33", key: environment.credentialKey)
        var bytes = good.combined; bytes[bytes.count - 1] ^= 1
        let bad = AICredentialEnvelope(formatVersion: fault == "format" ? 99 : 1,
            keyVersion: fault == "key" ? 99 : 1, combined: fault == "authentication" ? bytes : good.combined)
        var broken = try #require(initial.aiServices.configurations[.responses])
        broken.credential = bad; broken.credentialVersion = 9
        var readable = try #require(initial.aiServices.configurations[.messages])
        readable.credential = good; readable.credentialVersion = 2
        try await database.saveAIService(broken); try await database.saveAIService(readable)
        await database.close(); try historicalSchema(4, at: environment.databaseURL)
        let upgraded = DailyReportDatabase(directory: environment.directory, credentialCodec: AICredentialCodec(key: environment.credentialKey))
        let loaded = try await upgraded.load()
        #expect(loaded.aiServices.configurations[.responses] == broken)
        #expect(loaded.aiServices.configurations[.messages]?.credential?.formatVersion == 2)
        let flow = databaseAIFlow(upgraded, environment: environment)
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        if case .unreadable = flow.aiCredentialStatus { } else { Issue.record("坏凭据应局部不可读") }
        flow.send(.selectAIServiceType(.messages))
        #expect(flow.aiCredentialStatus == .readable)
        #expect(flow.isStorageReady)
        await upgraded.close()
    }

    @Test func offlineWholeDirectoryRestoreCanBringBackDeletedReportsKeysAndSettingsWithoutRequests() async throws {
        let environment = try IsolatedTestEnvironment(), backup = try IsolatedTestEnvironment()
        defer { environment.close(); backup.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let initial = try await database.load()
        let day = try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Asia/Shanghai")
        let report = SavedDailyReport(day: day, markdown: "SYNTHETIC_OLD_COPY_33", savedAt: environment.clock.now, lastEditedAt: nil)
        var settings = initial.generalSettings
        settings.generationPreferences = "SYNTHETIC_OLD_PREFERENCES_33"
        var service = try #require(initial.aiServices.configurations[.responses])
        service.configuration.endpoint = "https://example.invalid/restore"
        service.configuration.model = "synthetic-restore"
        service.credential = try await AIServiceCredentialCipher(key: environment.credentialKey).seal("SYNTHETIC_OLD_COPY_KEY_33")
        service.credentialVersion = 3
        service.validation = AIServiceValidation(status: .validated, baseline: service.requestBaseline, checkedAt: environment.clock.now,
            streaming: .supported, structured: .unsupported)
        try await database.save(report); try await database.saveGeneralSettings(settings)
        try await database.saveAIService(service); try await database.saveCurrentAIService(.responses)
        await database.close()
        try FileManager.default.removeItem(at: backup.directory)
        try FileManager.default.copyItem(at: environment.directory, to: backup.directory)
        try await database.deleteReports(day: nil)
        #expect(try await database.load().reports.isEmpty)
        await database.close()
        try FileManager.default.removeItem(at: environment.directory)
        try FileManager.default.copyItem(at: backup.directory, to: environment.directory)
        let restored = DailyReportDatabase(directory: environment.directory)
        let loaded = try await restored.load()
        #expect(loaded.reports == [report])
        #expect(loaded.generalSettings == settings)
        #expect(loaded.aiServices.configurations[.responses] == service)
        let flow = databaseAIFlow(restored, environment: environment)
        flow.send(.open(.report)); flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        #expect(flow.codexSourceStatus == .unchecked)
        #expect(flow.savedAIService.hasMatchingValidation)
        #expect(flow.aiCredentialStatus == .readable)
        #expect(flow.contentCounts == ReportContentCounts(saved: 1, drafts: 0, snapshots: 0))
        await restored.close()
    }

    @Test(arguments: ["management-reset-intent", "management-reset-removed", "management-reset-initialized"])
    func interruptedResetResumesUnderTheDirectoryLockAndLeavesNoBackup(_ scenario: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 86)
        #expect(FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("reset-intent").path))
        let database = DailyReportDatabase(directory: environment.directory)
        let loaded = try await database.load()
        #expect(loaded.reports.isEmpty && loaded.aiServices.current == nil)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)) == ["reports.sqlite", "storage.lock"])
        await database.close()
    }

    @Test(arguments: ["management-journal-crash", "management-migration-crash"])
    func sqliteRecoversHotJournalBeforeValidatingOrMigrating(_ scenario: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 86)
        let journal = environment.directory.appendingPathComponent("reports.sqlite-journal")
        #expect(try Data(contentsOf: journal).count > 512)
        let database = DailyReportDatabase(directory: environment.directory)
        let loaded = try await database.load()
        #expect(loaded.reports.count == 1)
        #expect(loaded.reports.first?.markdown == "SYNTHETIC_ORIGINAL_33\n")
        #expect(try storageInteger("PRAGMA user_version", at: environment.databaseURL) == 5)
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        await database.close()
    }

    @Test func realMigrationCommitFailureRollsBackAndCanBeRetried() throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe("management-migration-commit", directory: environment.directory) == 0)
    }

    @Test(arguments: [false, true])
    func realDeletionRollsBackCommitFailureAndClearPreservesAllSettings(_ all: Bool) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let initial = try await database.load()
        let day = try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Asia/Shanghai")
        let other = try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Etc/UTC")
        let reports = [day, other].map { SavedDailyReport(day: $0, markdown: "SYNTHETIC_DELETE_TRANSACTION_33", savedAt: environment.clock.now, lastEditedAt: nil) }
        for report in reports { try await database.save(report) }
        #expect(try runStorageProbe("management-reset-occupied", directory: environment.directory) == 73)
        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(environment.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM reports", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: ReportStorageError.writeFailed) { try await database.deleteReports(day: all ? nil : day) }
        #expect(Set(try await database.load().reports.map(\.day)) == [day, other])
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        try await database.deleteReports(day: all ? nil : day)
        let after = try await database.load()
        #expect(Set(after.reports.map(\.day)) == (all ? [] : [other]))
        #expect(after.generalSettings == initial.generalSettings)
        #expect(after.aiServices == initial.aiServices)
        #expect(after.codexSource == initial.codexSource)
        await database.close()
    }

    @Test func olderKeyRemainsReadableAndFailedReencryptionRollsBackTheEnvelopeAndSchema() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let envelope = try legacyCredential("SYNTHETIC_OLD_KEY_33", key: environment.credentialKey)
        let rotated = AIServiceCredentialCipher(key: Data(repeating: 0x32, count: 32), keyVersion: 2, legacyKeys: [1: environment.credentialKey])
        #expect(try await rotated.open(envelope) == "SYNTHETIC_OLD_KEY_33")
        #expect(try await rotated.seal("新测试值").keyVersion == 2)
        let database = DailyReportDatabase(directory: environment.directory)
        var service = try #require(try await database.load().aiServices.configurations[.messages])
        service.credential = envelope; service.credentialVersion = 3
        try await database.saveAIService(service); await database.close()
        try historicalSchema(4, at: environment.databaseURL)
        let before = try Data(contentsOf: environment.databaseURL)
        let failing = DailyReportDatabase(directory: environment.directory,
            credentialCodec: AICredentialCodec(key: Data(), keyVersion: 2, legacyKeys: [1: environment.credentialKey]))
        await #expect(throws: ReportStorageError.migrationFailed) { _ = try await failing.load() }
        #expect(try Data(contentsOf: environment.databaseURL) == before)
        #expect(try storageInteger("PRAGMA user_version", at: environment.databaseURL) == 4)
        await failing.close()
    }

    @Test func resetFailureKeepsExclusiveOwnershipAndResumesOnlyTheConfirmedReset() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory, resetProgress: { phase in
            if phase == .filesRemoved { throw ReportStorageError.writeFailed }
        })
        _ = try await database.load()
        try await database.save(SavedDailyReport(day: ReportDay(date: environment.clock.now, timeZone: .gmt),
            markdown: "仅测试库 SYNTHETIC_RESET_33", savedAt: environment.clock.now, lastEditedAt: nil))
        await #expect(throws: ReportStorageError.resetIncomplete) { _ = try await database.reset() }
        #expect(try runStorageProbe("open", directory: environment.directory) == 73)
        let marker = try Data(contentsOf: environment.directory.appendingPathComponent("reset-intent"))
        #expect(String(decoding: marker, as: UTF8.self) == "DailyReports.reset.v1\n")
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        let fresh = try await reopened.load()
        #expect(fresh.reports.isEmpty)
        #expect(fresh.generalSettings == DailyReportGeneralSettings())
        #expect(fresh.aiServices.current == nil)
        #expect(!FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("reset-intent").path))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)) == ["reports.sqlite", "storage.lock"])
        await reopened.close()
    }

    // Historical shapes come from #23 (schema 1), #24 (2), #25 (3), #27 (4).
    @Test(arguments: [1, 2, 3, 4])
    func upgradesRealHistoricalSchemasWithoutChangingRawReports(_ version: Int) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        _ = try await database.load()
        let day = try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Asia/Shanghai")
        let report = SavedDailyReport(day: day, markdown: "  历史\u{0}é👩🏽‍💻\n", savedAt: Date(timeIntervalSince1970: 100), lastEditedAt: nil)
        try await database.save(report)
        await database.close()
        try historicalSchema(version, at: environment.databaseURL)
        let upgraded = DailyReportDatabase(directory: environment.directory)
        let loaded = try await upgraded.load()
        #expect(loaded.reports == [report])
        #expect(loaded.aiServices.configurations.count == 3)
        #expect(loaded.generalSettings == DailyReportGeneralSettings())
        #expect(try storageInteger("PRAGMA user_version", at: environment.databaseURL) == 5)
        await upgraded.close()
    }

    @Test func rewrapsReadableLegacyCredentialsWithoutChangingLogicalVersionOrProof() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        var snapshot = try await database.load()
        var service = try #require(snapshot.aiServices.configurations[.responses])
        service.configuration.endpoint = "https://example.invalid/legacy/?route=exact"
        service.configuration.model = "synthetic-legacy-33"
        service.credential = try legacyCredential("SYNTHETIC_LEGACY_KEY_33", key: environment.credentialKey)
        service.credentialVersion = 7
        service.validation = AIServiceValidation(status: .validated, baseline: service.requestBaseline, checkedAt: environment.clock.now,
                                                 streaming: .supported, structured: .unsupported)
        try await database.saveAIService(service)
        try await database.saveCurrentAIService(.responses)
        await database.close()
        try historicalSchema(4, at: environment.databaseURL)
        let upgraded = DailyReportDatabase(directory: environment.directory, credentialCodec: AICredentialCodec(key: environment.credentialKey))
        snapshot = try await upgraded.load()
        let restored = try #require(snapshot.aiServices.configurations[.responses])
        #expect(restored.configuration == service.configuration)
        #expect(restored.credentialVersion == 7)
        #expect(restored.validation == service.validation)
        #expect(snapshot.aiServices.current == .responses)
        #expect(restored.credential?.formatVersion == 2)
        #expect(try await AIServiceCredentialCipher(key: environment.credentialKey).open(try #require(restored.credential)) == "SYNTHETIC_LEGACY_KEY_33")
        await upgraded.close()
    }
}

func legacyCredential(_ text: String, key: Data, keyVersion: Int = 1) throws -> AICredentialEnvelope {
    let box = try AES.GCM.seal(Data(text.utf8), using: SymmetricKey(data: key),
        authenticating: Data("DailyReports.AICredential.format1.key\(keyVersion)".utf8))
    return AICredentialEnvelope(formatVersion: 1, keyVersion: keyVersion, combined: try #require(box.combined))
}

func historicalSchema(_ version: Int, at url: URL) throws {
    if version < 4 { try storageSQL("DROP TABLE ai_services; DROP TABLE ai_selection", at: url) }
    if version < 3 { try storageSQL("DROP TABLE codex_source", at: url) }
    if version < 2 { try storageSQL("DROP TABLE general_settings", at: url) }
    try storageSQL("PRAGMA user_version=\(version)", at: url)
}

func storageSQL(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
}

func storageInteger(_ sql: String, at url: URL) throws -> Int32 {
    var database: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    return sqlite3_column_int(statement, 0)
}
