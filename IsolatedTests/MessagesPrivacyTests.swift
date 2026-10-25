import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct MessagesPrivacyTests {
    @Test func nativeMessagesKeepsSensitiveDataAtItsAllowedExitsAcrossGenerationFailureAndSave() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let credentials = AIServiceCredentialCipher(key: environment.credentialKey)
        let codex = ControlledCodexSource(), log = DDLog(), memory = MemoryWindowLogger(); log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        let key = "sk-SYNTHETIC30abcdefghijklmnopqrstuvwxyz"
        let access = AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
        var copies: [String] = []
        let flow = DailyReportFlow(storage: database, aiCredentials: credentials, aiAccess: access, reportTokenizer: OfflineReportTokenizer(),
            codexSourceAccess: codex, now: { environment.clock.now }, timeZone: .gmt,
            performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in }, recordCodexCheck: { _ in },
            recordSessionScan: { _ in }, recordAIStorage: { telemetry.storageFinished($0) },
            recordAIValidation: { telemetry.validationFinished($0) }, recordGeneration: { telemetry.generationChanged($0) },
            redactCredentials: CredentialRedaction.redact, copyText: { copies.append($0) })
        flow.send(.open(.settings)); flow.send(.open(.report)); await flow.waitForStorage()
        let session = try #require(flow.openWindows[.settings])
        flow.send(.requestSettingsPage(.general))
        var general = flow.generalSettingsEdit; general.generationPreferences = "PREFERENCES_PRIVATE_30"
        flow.send(.editGeneralSettings(general, session: session)); flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = environment.transport.endpoint.absoluteString
        edit.configuration.model = "MODEL_PRIVATE_30"; edit.newCredential = key; edit.temperature = "0"
        edit.configuration.defaults = .messages(.init(thinking: .adaptive, effort: .high))
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision)); flow.send(.saveAIService); await flow.waitForStorage()
        #expect(environment.transport.requests.isEmpty)
        environment.transport.enqueue(MessagesFixture.completion("OK"))
        environment.transport.enqueue(MessagesFixture.sse(MessagesFixture.events("OK")))
        environment.transport.enqueue(MessagesFixture.completion(#"{"ok":"OK"}"#))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource)); flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        await codex.setScan(.init(sessions: [syntheticCandidate("SOURCE_ID_PRIVATE_30",
            user: "RAW_WORK_PRIVATE_30 当天完成合成文档 \(key)", directory: "/SOURCE_DIRECTORY_PRIVATE_30")], failures: [], version: nil))
        flow.send(.scanSessions); await flow.waitForSessionScan(); flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let payload = syntheticReportPayload.replacingOccurrences(of: "合成进展", with: "合成进展 \(key)")
        environment.transport.enqueue(MessagesFixture.sse(MessagesFixture.events(payload)))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationSources != nil && !flow.body.contains(key))
        #expect(try await database.load().reports.isEmpty)
        let original = flow.body, titles = flow.generationSources?.groups.first?.titles
        environment.transport.enqueue(Data(#"{"type":"error","error":{"type":"overloaded_error","message":"RAW_ERROR_PRIVATE_30"}}"#.utf8), statusCode: 529)
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.body == original && flow.generationSources?.groups.first?.titles == titles && flow.generationError == .unavailable)
        #expect(flow.currentAIService == .messages && flow.savedAIService.hasMatchingValidation)
        let requests = environment.transport.requests
        #expect(requests.count == 5)
        #expect(await codex.scanCount == 1)
        for (index, request) in requests.enumerated() {
            #expect(request.url == environment.transport.endpoint && request.value(forHTTPHeaderField: "x-api-key") == key)
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" && request.value(forHTTPHeaderField: "Authorization") == nil)
            let data = try body(of: request), raw = String(decoding: data, as: UTF8.self)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["model"] as? String == "MODEL_PRIVATE_30" && object["max_tokens"] as? Int == 16_384 && object["temperature"] as? Double == 0)
            #expect((object["thinking"] as? [String: Any])?["type"] as? String == "adaptive")
            #expect((object["output_config"] as? [String: Any])?["effort"] as? String == "high")
            #expect(["store", "truncation", "reasoning", "response_format", "max_output_tokens"].allSatisfy { object[$0] == nil })
            #expect(!raw.contains(key) && !raw.contains("SOURCE_ID_PRIVATE_30") && !raw.contains("SOURCE_DIRECTORY_PRIVATE_30"))
            if index < 3 { #expect(!raw.contains("RAW_WORK_PRIVATE_30") && !raw.contains("PREFERENCES_PRIVATE_30")) }
            else { #expect(raw.contains("RAW_WORK_PRIVATE_30") && raw.contains("PREFERENCES_PRIVATE_30")) }
        }
        let reportSession = try #require(flow.openWindows[.report])
        flow.send(.editBody(flow.body + "\n\n明确手工修改", day: flow.selectedDay, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.copyMarkdown); #expect(copies == [flow.body] && flow.generationSources != nil)
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        #expect(try await database.load().reports.first?.markdown == flow.body)
        let forbidden = [key, "RAW_WORK_PRIVATE_30", "SOURCE_ID_PRIVATE_30", "SOURCE_DIRECTORY_PRIVATE_30", "RAW_ERROR_PRIVATE_30",
                         "PRIVATE_THINKING_30", "PRIVATE_SIGNATURE_30", "PRIVATE_REDACTED_30"]
        for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: file)
            #expect(forbidden.allSatisfy { data.range(of: Data($0.utf8)) == nil })
        }
        let preferences = String(describing: environment.defaults.dictionaryRepresentation())
        #expect((forbidden + ["PREFERENCES_PRIVATE_30", "MODEL_PRIVATE_30", environment.transport.endpoint.absoluteString])
            .allSatisfy { !preferences.contains($0) })
        log.flushLog()
        let messages = memory.snapshot(), probes = messages.filter { $0.function == "ai_validation_finished" }
        try expectOnlyWhitelistedTelemetry(messages, forbidden: forbidden + ["PREFERENCES_PRIVATE_30", "MODEL_PRIVATE_30",
            environment.transport.endpoint.absoluteString, environment.credentialKey.base64EncodedString(), payload, flow.body])
        #expect(probes.count == 3 && probes.allSatisfy { $0.message.contains("service=messages") })
        for message in messages {
            let secrets = forbidden + ["PREFERENCES_PRIVATE_30", "MODEL_PRIVATE_30", environment.transport.endpoint.absoluteString,
                                       environment.credentialKey.base64EncodedString(), payload, flow.body]
            #expect(secrets.allSatisfy { !message.message.contains($0) && !message.messageFormat.contains($0) && !(message.function ?? "").contains($0) })
            #expect(message.file == "DailyReports" && message.line == 0 && message.context == 0 && message.representedObject == nil)
        }
        #expect(memory.logFormatter == nil)
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        let restored = try await reopened.load()
        #expect(restored.aiServices.current == .messages && restored.aiServices.configurations[.messages]?.hasMatchingValidation == true)
        #expect(restored.reports.first?.markdown == flow.body)
        #expect(AIServiceType.allCases.filter { $0 != .messages }.allSatisfy { restored.aiServices.configurations[$0]?.credential == nil })
        await reopened.close()
    }
}
