import CocoaLumberjack
import Foundation
import SQLite3
import Testing
@testable import random_thoughts

@MainActor
struct ReportGenerationPrivacyTests {
    @Test func realStorageAndLogObjectsKeepRequestsAndSourcesTransientAndSavingFailureRetainsTheDraft() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let credentials = AIServiceCredentialCipher(key: environment.credentialKey)
        let access = ControlledAIService(), codex = ControlledCodexSource()
        let log = DDLog(), memory = MemoryWindowLogger(); log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        var copies: [String] = []
        let flow = DailyReportFlow(storage: database, aiCredentials: credentials, aiAccess: access, reportTokenizer: OfflineReportTokenizer(),
            codexSourceAccess: codex, now: { environment.clock.now }, timeZone: .gmt,
            performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in }, recordCodexCheck: { _ in },
            recordSessionScan: { _ in }, recordAIStorage: { telemetry.storageFinished($0) },
            recordAIValidation: { telemetry.validationFinished($0) }, recordGeneration: { telemetry.generationChanged($0) },
            redactCredentials: { try CredentialRedaction.redact($0) }, copyText: { copies.append($0) })
        flow.send(.open(.settings)); flow.send(.open(.report)); await flow.waitForStorage()
        let session = try #require(flow.openWindows[.settings])
        let key = "sk-SYNTHETIC28abcdefghijklmnopqrstuvwxyz"
        flow.send(.requestSettingsPage(.aiServices))
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = "https://ENDPOINT_PRIVATE_28.invalid/final?query=QUERY_PRIVATE_28"
        edit.configuration.model = "MODEL_PRIVATE_28"; edit.newCredential = key
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision)); flow.send(.saveAIService)
        await flow.waitForStorage()
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        var settings = flow.generalSettingsEdit; settings.generationPreferences = "PREFERENCES_PRIVATE_28"
        flow.send(.editGeneralSettings(settings, session: session)); flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource)); flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        let candidate = syntheticCandidate("SOURCE_ID_PRIVATE_28", user: "RAW_WORK_PRIVATE_28 当天完成合成事项 \(key)", directory: "/SOURCE_DIRECTORY_PRIVATE_28")
        await codex.setScan(.init(sessions: [candidate], failures: [], version: nil))
        flow.send(.scanSessions); await flow.waitForSessionScan(); flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let payload = try JSONSerialization.data(withJSONObject: ["overview": "完成合成事项 \(key)", "completed": "完成合成事项", "deliverables": "", "decisions": "", "risks": "", "plans": ""])
        await access.enqueue(.success(String(decoding: payload, as: UTF8.self)))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationSources != nil)
        #expect(!flow.body.contains(key))
        #expect(try await database.load().reports.isEmpty)
        flow.send(.copyMarkdown); #expect(copies == [flow.body])
        let requests = await access.requests
        #expect(requests.count == 4)
        #expect(requests.prefix(3).allSatisfy { !$0.input.contains("RAW_WORK_PRIVATE_28") && !$0.instruction.contains("PREFERENCES_PRIVATE_28") })
        let work = try #require(requests.last)
        #expect(work.credential == key)
        #expect(work.input.contains("RAW_WORK_PRIVATE_28") && !work.input.contains(key))
        #expect(!work.input.contains("SOURCE_ID_PRIVATE_28") && !work.input.contains("SOURCE_DIRECTORY_PRIVATE_28"))
        let original = flow.body
        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(environment.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM reports", nil, nil, nil) == SQLITE_OK)
        flow.send(.save); await flow.waitForStorage()
        #expect(flow.storageError == .writeFailed && flow.hasDraft && flow.generationSources != nil)
        #expect(flow.body == original)
        #expect(await access.requests.count == 4)
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        #expect(try await database.load().reports.first?.markdown == original)
        #expect(await codex.scanCount == 1)
        let forbiddenDisk = [key, "RAW_WORK_PRIVATE_28", "SOURCE_ID_PRIVATE_28", "SOURCE_DIRECTORY_PRIVATE_28", "合成 SOURCE_ID_PRIVATE_28"]
        for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            for value in forbiddenDisk { #expect(bytes.range(of: Data(value.utf8)) == nil) }
        }
        log.flushLog()
        let messages = memory.snapshot()
        let forbiddenLog = forbiddenDisk + ["PREFERENCES_PRIVATE_28", "ENDPOINT_PRIVATE_28", "QUERY_PRIVATE_28", "MODEL_PRIVATE_28", original, environment.credentialKey.base64EncodedString()]
        #expect(messages.contains { $0.function == "ai_validation_finished" })
        #expect(messages.contains { $0.function == "report_generation_finished" })
        for message in messages {
            #expect(forbiddenLog.allSatisfy { !message.message.contains($0) && !message.messageFormat.contains($0) })
            #expect(message.file == "DailyReports" && message.line == 0 && message.context == 0 && message.representedObject == nil)
        }
        #expect(memory.logFormatter == nil)
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        let restored = try await reopened.load()
        #expect(restored.reports.first?.markdown == original)
        #expect(restored.aiServices.configurations[.chatCompletions]?.hasMatchingValidation == true)
        await reopened.close()
    }
}
