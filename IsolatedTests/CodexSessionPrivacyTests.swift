import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct CodexSessionPrivacyTests {
    @Test(arguments: ["handshake", "malformed", "read"])
    func rawStdioAndServerFailuresProduceOnlyFixedLogFields(_ scenario: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let reader = try scanReader(environment, fixture: ["scenario": scenario])
        let source = try scanIdentity(environment)
        let database = DailyReportDatabase(directory: environment.directory.appendingPathComponent("storage"))
        _ = try await database.load()
        try await database.saveCodexSource(.init(configuration: .init(mode: .manual,
            executablePath: source.executablePath, explicitDirectory: source.dataDirectory), resolvedDirectory: source.dataDirectory))
        let log = DDLog(), memory = MemoryWindowLogger(); log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        let flow = DailyReportFlow(storage: database, aiCredentials: AIServiceCredentialCipher(key: environment.credentialKey),
            aiAccess: ControlledAIService(), reportTokenizer: OfflineReportTokenizer(), codexSourceAccess: reader,
            now: { environment.clock.now }, timeZone: .gmt, performWindowEffect: { _ in }, performContextEffect: { _ in },
            recordWindowMode: { _ in }, recordCodexCheck: { telemetry.codexCheckFinished($0) },
            recordSessionScan: { telemetry.sessionScanFinished($0) }, recordAIStorage: { telemetry.storageFinished($0) },
            recordAIValidation: { _ in }, recordGeneration: { _ in }, redactCredentials: CredentialRedaction.redact, copyText: { _ in })
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource)); flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        log.flushLog()
        let messages = memory.snapshot()
        #expect(messages.contains { $0.function == "codex_check_finished" && $0.message.contains("result=failure") })
        try expectOnlyWhitelistedTelemetry(messages, forbidden: ["STDERR_SECRET_25", "STDOUT_SECRET_25", "ERROR_SECRET_25",
            "RAW_SECRET_25", "NOTIFICATION_SECRET_25", source.executablePath, source.dataDirectory])
        await database.close()
    }

    @Test func realWireThroughTheFlowKeepsSnapshotsOutOfSQLitePreferencesAndLogObjects() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let markers = ["BODY_MEMORY_ONLY_26", "TITLE_MEMORY_ONLY_26", "WORKTREE_MEMORY_ONLY_26", "SESSION_MEMORY_ONLY_26"]
        let thread = syntheticSession(id: markers[3], name: markers[1], cwd: "/synthetic/" + markers[2],
                                     turns: [syntheticTurn(id: "turn", at: 1000, user: markers[0])])
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "currentPages": [[thread]], "archivedPages": [[]],
                                                          "threads": [markers[3]: thread]])
        let source = try scanIdentity(environment)
        let storageDirectory = environment.directory.appendingPathComponent("storage")
        let database = DailyReportDatabase(directory: storageDirectory)
        do {
            _ = try await database.load()
            try await database.saveCodexSource(CodexDataSourceSettings(configuration: CodexDataSourceConfiguration(
                mode: .manual, executablePath: source.executablePath, explicitDirectory: source.dataDirectory
            ), resolvedDirectory: source.dataDirectory))
            let log = DDLog()
            let memory = MemoryWindowLogger()
            log.add(memory)
            let telemetry = DailyReportTelemetry(log: log)
            let flow = DailyReportFlow(storage: database, aiCredentials: AIServiceCredentialCipher(key: Data(repeating: 0x21, count: 32)),
                aiAccess: ControlledAIService(), reportTokenizer: OfflineReportTokenizer(), codexSourceAccess: reader, now: { environment.clock.now }, timeZone: .gmt,
                performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in },
                recordCodexCheck: { telemetry.codexCheckFinished($0) }, recordSessionScan: { telemetry.sessionScanFinished($0) },
                recordAIStorage: { telemetry.storageFinished($0) },
                recordAIValidation: { _ in }, recordGeneration: { _ in }, redactCredentials: CredentialRedaction.redact, copyText: { _ in })
            flow.send(.open(.report))
            await flow.waitForStorage()
            #expect(flow.codexSourceStatus == .unchecked)
            flow.send(.scanSessions)
            await flow.waitForSessionScan()
            #expect(flow.codexSourceStatus == .available)
            flow.send(.confirmSessionSelection)
            await flow.waitForSessionScan()
            #expect(flow.confirmedSnapshot?.sessions[0].turns[0].userText == markers[0])
            let session = try #require(flow.openWindows[.report])
            flow.send(.editBody("用户明确保存的合成日报", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
            flow.send(.save)
            await flow.waitForStorage()
            #expect(flow.savedReports[flow.selectedDay]?.markdown == "用户明确保存的合成日报")
            for file in try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
                let bytes = try Data(contentsOf: file)
                let text = String(decoding: bytes, as: UTF8.self)
                #expect(markers.allSatisfy { !text.contains($0) && !file.lastPathComponent.contains($0) })
            }
            let preferences = String(describing: environment.defaults.dictionaryRepresentation())
            #expect(markers.allSatisfy { !preferences.contains($0) })
            log.flushLog()
            let messages = memory.snapshot()
            try expectOnlyWhitelistedTelemetry(messages, forbidden: markers + ["STDERR_SECRET_25", "STDOUT_SECRET_25", "ERROR_SECRET_25", "RAW_SECRET_25", "USER_AGENT_SECRET_25"])
            #expect(messages.map(\.message) == ["session_scan_finished result=complete candidates=1 succeeded=1 failed=0"])
            for message in messages {
                #expect(markers.allSatisfy { !message.message.contains($0) && !message.file.contains($0) && !(message.function ?? "").contains($0) })
                #expect(!message.message.contains("SECRET_25"))
                #expect(message.representedObject == nil)
            }
            flow.send(.windowClosed(.report, session: session))
            flow.send(.open(.report))
            #expect(flow.confirmedSnapshot == nil && flow.sessionScan == nil)
            #expect(try String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8) == "1")
            await database.close()
        } catch {
            await database.close()
            throw error
        }
    }
}
