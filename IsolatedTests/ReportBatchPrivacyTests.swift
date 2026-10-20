import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportBatchPrivacyTests {
    @Test func intermediateFactsStayOutOfRealStorageLogsClipboardAndTheDraft() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let credentials = AIServiceCredentialCipher(key: environment.credentialKey)
        let access = BatchAIService(mode: .privateSummary), codex = ControlledCodexSource()
        let key = "sk-SYNTHETIC31abcdefghijklmnopqrstuvwxyz"
        _ = try await database.load()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://ENDPOINT_PRIVATE_31.invalid/final?query=QUERY_PRIVATE_31"
        saved.configuration.model = "MODEL_PRIVATE_31"
        saved.configuration.totalBudget = 12_000; saved.configuration.outputLimit = 3_000
        saved.credential = try await credentials.seal(key); saved.credentialVersion = 1
        saved.validation = .init(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.clock.now,
            streaming: .unsupported, structured: .supported)
        try await database.saveAIService(saved); try await database.saveCurrentAIService(.chatCompletions)
        var settings = DailyReportGeneralSettings(); settings.generationPreferences = "PREFERENCES_PRIVATE_31"
        try await database.saveGeneralSettings(settings)
        let log = DDLog(), memory = MemoryWindowLogger(); log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        var copies: [String] = []
        let flow = DailyReportFlow(storage: database, aiCredentials: credentials, aiAccess: access, reportTokenizer: OfflineReportTokenizer(),
            codexSourceAccess: codex, now: { environment.clock.now }, timeZone: .gmt,
            performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in }, recordCodexCheck: { _ in },
            recordSessionScan: { _ in }, recordAIStorage: { telemetry.storageFinished($0) },
            recordAIValidation: { telemetry.validationFinished($0) }, recordGeneration: { telemetry.generationChanged($0) },
            redactCredentials: CredentialRedaction.redact, copyText: { copies.append($0) })
        flow.send(.open(.settings)); flow.send(.open(.report)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource)); flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        let candidate = syntheticCandidate("SOURCE_ID_PRIVATE_31", user: "RAW_WORK_PRIVATE_31 \(key)" + String(repeating: " evidence", count: 40_000), directory: "/SOURCE_DIRECTORY_PRIVATE_31")
        await codex.setScan(.init(sessions: [candidate], failures: [], version: nil))
        flow.send(.scanSessions); await flow.waitForSessionScan(); flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(await access.requests.isEmpty)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationSources != nil && flow.generationError == nil)
        #expect(!flow.body.contains("INTERMEDIATE_PRIVATE_31"))
        #expect(try await database.load().reports.isEmpty)
        flow.send(.copyMarkdown); #expect(copies == [flow.body])
        let requests = await access.requests
        #expect(requests.allSatisfy { $0.credential == key && !$0.input.contains(key) && !$0.additionalInputs.contains(where: { $0.contains(key) }) })
        #expect(requests.last?.additionalInputs.contains(where: { $0.contains("INTERMEDIATE_PRIVATE_31") && $0.contains("[已遮盖凭据]") }) == true)
        #expect(requests.allSatisfy { !$0.input.contains("SOURCE_ID_PRIVATE_31") && !$0.input.contains("SOURCE_DIRECTORY_PRIVATE_31") })
        let originalBody = flow.body, originalSources = flow.generationSources
        for failing in [true, false] {
            let before = await access.requests.count
            await access.hold(stage: .extracting)
            flow.send(.generateReport); await flow.waitForGeneration()
            flow.send(.confirm(try #require(flow.confirmation).id)); await access.waitForRequests(before + 3)
            if failing { await access.release(before, failure: .network) }
            else { flow.send(.cancelGeneration) }
            await flow.waitForGeneration(); await access.releaseAll()
            #expect(flow.body == originalBody)
            #expect(flow.generationSources?.groups.map(\.titles) == originalSources?.groups.map(\.titles))
            #expect(flow.generationSources?.groups.map(\.directory) == originalSources?.groups.map(\.directory))
            #expect(flow.generationSources?.historyDays == originalSources?.historyDays)
            #expect(flow.generationError == (failing ? .network : .cancelled))
            #expect(try await database.load().reports.isEmpty)
        }
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        let forbiddenDisk = [key, "RAW_WORK_PRIVATE_31", "INTERMEDIATE_PRIVATE_31", "SOURCE_ID_PRIVATE_31", "SOURCE_DIRECTORY_PRIVATE_31"]
        for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            for value in forbiddenDisk { #expect(bytes.range(of: Data(value.utf8)) == nil) }
        }
        log.flushLog()
        let messages = memory.snapshot()
        let forbiddenLog = forbiddenDisk + ["PREFERENCES_PRIVATE_31", "ENDPOINT_PRIVATE_31", "QUERY_PRIVATE_31", "MODEL_PRIVATE_31", environment.credentialKey.base64EncodedString()]
        #expect(messages.contains { $0.message.contains("path=batched") && $0.message.contains("result=success") })
        #expect(messages.contains { $0.message.contains("result=failure") })
        #expect(messages.contains { $0.message.contains("result=cancelled") })
        for message in messages {
            #expect(forbiddenLog.allSatisfy { !message.message.contains($0) && !message.messageFormat.contains($0) })
            #expect(message.file == "DailyReports" && message.line == 0 && message.context == 0 && message.representedObject == nil)
        }
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        #expect(try await reopened.load().reports.first?.markdown == flow.body)
        await reopened.close()
        #expect(await codex.scanCount == 1)
    }
}
