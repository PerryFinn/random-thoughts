import Foundation
import SQLite3
import Testing
@testable import random_thoughts

@MainActor
struct AIServicePersistenceTests {
    @Test func realSQLiteRollsBackConfigurationCredentialProofAndDeletionTogetherAndReopensWithoutPlaintext() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        _ = try await database.load()
        let cipher = AIServiceCredentialCipher(key: environment.credentialKey)
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .responses))
        saved.configuration.endpoint = "https://example.invalid/Exact/?query=a%2Fb&trailing=1"
        saved.configuration.model = "synthetic-persistence"
        saved.configuration.defaults = .responses(ResponsesDefaults(temperature: 0, reasoningEffort: AIReasoningEffort.none))
        saved.credential = try await cipher.seal("SYNTHETIC_SQLITE_OLD_KEY_27")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.clock.now,
                                              streaming: .supported, structured: .unsupported)
        try await database.saveAIService(saved)
        try await database.saveCurrentAIService(.responses)
        let flow = databaseAIFlow(database, environment: environment)
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        let session = try #require(flow.openWindows[.settings])
        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(environment.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM ai_services", nil, nil, nil) == SQLITE_OK)
        var edit = flow.aiServiceEdit
        edit.configuration.model = "synthetic-replaced"
        edit.newCredential = "SYNTHETIC_SQLITE_NEW_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.aiServiceStorageError == .writeFailed)
        #expect(flow.savedAIService == saved)
        #expect(flow.aiServiceEdit == edit)
        #expect(try await database.load().aiServices.configurations[.responses] == saved)
        try assertNoCredentialPlaintext(environment, markers: ["SYNTHETIC_SQLITE_OLD_KEY_27", "SYNTHETIC_SQLITE_NEW_KEY_27"])
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        flow.send(.saveAIService); await flow.waitForStorage()
        let replaced = flow.savedAIService
        #expect(replaced.credentialVersion == 2)
        #expect(replaced.validation.status == .needsRevalidation)
        #expect(try await cipher.open(try #require(replaced.credential)) == "SYNTHETIC_SQLITE_NEW_KEY_27")
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM ai_services", nil, nil, nil) == SQLITE_OK)
        flow.send(.requestDeleteAICredential)
        flow.send(.confirm(try #require(flow.confirmation?.id))); await flow.waitForStorage()
        #expect(flow.savedAIService == replaced)
        #expect(try await database.load().aiServices.configurations[.responses] == replaced)
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        flow.send(.requestDeleteAICredential)
        flow.send(.confirm(try #require(flow.confirmation?.id))); await flow.waitForStorage()
        #expect(flow.savedAIService.credential == nil)
        #expect(flow.savedAIService.credentialVersion == 3)
        #expect(flow.currentAIService == .responses)
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        let restored = try await reopened.load()
        #expect(restored.aiServices.configurations[.responses] == flow.savedAIService)
        #expect(restored.aiServices.current == .responses)
        #expect(restored.aiServices.configurations.count == 3)
        try assertNoCredentialPlaintext(environment, markers: ["SYNTHETIC_SQLITE_OLD_KEY_27", "SYNTHETIC_SQLITE_NEW_KEY_27"])
        #expect(environment.defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SYNTHETIC_SQLITE") } == false)
        await reopened.close()
    }

    @Test(arguments: ["format", "key", "authentication", "short"])
    func unreadableCiphertextIsPreservedAndOnlyBlocksItsOwnService(_ fault: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let initial = try await database.load()
        let cipher = AIServiceCredentialCipher(key: environment.credentialKey)
        let sealed = try await cipher.seal("SYNTHETIC_UNREADABLE_KEY_27")
        var bytes = sealed.combined
        bytes[bytes.count - 1] ^= 1
        let bad: AICredentialEnvelope
        let expected: AICredentialError
        switch fault {
        case "format": bad = AICredentialEnvelope(formatVersion: 99, keyVersion: 1, combined: sealed.combined); expected = .unsupportedFormat
        case "key": bad = AICredentialEnvelope(formatVersion: 1, keyVersion: 99, combined: sealed.combined); expected = .unknownKeyVersion
        case "authentication": bad = AICredentialEnvelope(formatVersion: 1, keyVersion: 1, combined: bytes); expected = .authenticationFailed
        default: bad = AICredentialEnvelope(formatVersion: 1, keyVersion: 1, combined: Data()); expected = .authenticationFailed
        }
        var saved = initial.aiServices.configurations[.chatCompletions]!
        saved.configuration.endpoint = "https://example.invalid/chat"
        saved.configuration.model = "synthetic-unreadable"
        saved.credential = bad; saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.clock.now)
        try await database.saveAIService(saved); try await database.saveCurrentAIService(.chatCompletions)
        var other = initial.aiServices.configurations[.messages]!
        other.credential = sealed; other.credentialVersion = 1
        try await database.saveAIService(other)
        let report = SavedDailyReport(day: ReportDay(date: environment.clock.now, timeZone: .gmt), markdown: "明确保存的日报", savedAt: environment.clock.now, lastEditedAt: nil)
        try await database.save(report)
        let flow = databaseAIFlow(database, environment: environment)
        flow.send(.open(.settings)); flow.send(.open(.report)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices))
        #expect(flow.isStorageReady)
        #expect(flow.aiCredentialStatus == .unreadable(expected))
        #expect(flow.savedAIService.credential == bad)
        #expect(!flow.canMakeAIServiceCurrent)
        #expect(flow.savedReports[report.day] == report)
        flow.send(.showAICredential); flow.send(.copyAICredential); await flow.waitForAICredential()
        #expect(flow.revealedAICredential == nil)
        flow.send(.requestAIValidation)
        #expect(flow.aiCredentialError == expected)
        flow.send(.selectAIServiceType(.messages))
        #expect(flow.aiCredentialStatus == .readable)
        flow.send(.selectAIServiceType(.chatCompletions))
        #expect(try await database.load().aiServices.configurations[.chatCompletions]?.credential == bad)
        var edit = flow.aiServiceEdit; edit.newCredential = "SYNTHETIC_REPAIRED_KEY_27"
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.aiCredentialStatus == .readable)
        #expect(flow.savedAIService.credentialVersion == 2)
        #expect(flow.currentAIService == .chatCompletions)
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        await database.close()
    }

    @Test(arguments: ["ai-old-schema", "ai-missing-row", "ai-unknown-protocol", "ai-bad-record", "ai-bad-budget", "ai-bad-schema", "ai-missing-selection"])
    func malformedAIStoragePreservesTheOriginalDatabaseInDedicatedProcesses(_ scenario: String) throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 0)
    }
}

@MainActor
func databaseAIFlow(_ database: DailyReportDatabase, environment: IsolatedTestEnvironment) -> DailyReportFlow {
    DailyReportFlow(storage: database, aiCredentials: AIServiceCredentialCipher(key: environment.credentialKey),
                    aiAccess: ControlledAIService(), reportTokenizer: OfflineReportTokenizer(), codexSourceAccess: ControlledCodexSource(), now: { environment.clock.now }, timeZone: .gmt,
                    performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in },
                    recordCodexCheck: { _ in }, recordSessionScan: { _ in }, recordAIStorage: { _ in },
                    recordAIValidation: { _ in }, recordGeneration: { _ in }, redactCredentials: { $0 }, copyText: { _ in })
}

@MainActor
private func assertNoCredentialPlaintext(_ environment: IsolatedTestEnvironment, markers: [String]) throws {
    for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
        let bytes = try Data(contentsOf: file)
        for marker in markers { #expect(bytes.range(of: Data(marker.utf8)) == nil) }
    }
}
