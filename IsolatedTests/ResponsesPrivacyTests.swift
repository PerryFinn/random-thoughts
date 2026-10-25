import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ResponsesPrivacyTests {
    @Test func nativeValidationAndGenerationKeepCredentialsAndSourcesAtTheirAllowedExits() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let credentials = AIServiceCredentialCipher(key: environment.credentialKey)
        let codex = ControlledCodexSource(), log = DDLog(), memory = MemoryWindowLogger(); log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        let access = AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
        let key = "sk-SYNTHETIC29abcdefghijklmnopqrstuvwxyz"
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
        var general = flow.generalSettingsEdit; general.generationPreferences = "PREFERENCES_PRIVATE_29"
        flow.send(.editGeneralSettings(general, session: session)); flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = environment.transport.endpoint.absoluteString
        edit.configuration.model = "MODEL_PRIVATE_29"; edit.newCredential = key
        edit.configuration.defaults = .responses(.init(temperature: 0, reasoningEffort: AIReasoningEffort.none))
        edit.temperature = "0"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision)); flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(environment.transport.requests.isEmpty)
        environment.transport.enqueue(responsesCompletion("OK"))
        environment.transport.enqueue(ResponsesFixture.sse(ResponsesFixture.events("OK")))
        environment.transport.enqueue(responsesCompletion(#"{"ok":"OK"}"#))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource)); flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        await codex.setScan(.init(sessions: [syntheticCandidate("SOURCE_ID_PRIVATE_29",
            user: "RAW_WORK_PRIVATE_29 当天完成合成文档 \(key)", directory: "/SOURCE_DIRECTORY_PRIVATE_29")], failures: [], version: nil))
        flow.send(.scanSessions); await flow.waitForSessionScan(); flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let payload = syntheticReportPayload.replacingOccurrences(of: "合成进展", with: "合成进展 \(key)")
        environment.transport.enqueue(ResponsesFixture.sse(ResponsesFixture.events(payload)))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationSources != nil && !flow.body.contains(key))
        #expect(try await database.load().reports.isEmpty)
        let requests = environment.transport.requests
        #expect(requests.count == 4)
        for (index, request) in requests.enumerated() {
            #expect(request.url == environment.transport.endpoint)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
            let data = try body(of: request), raw = String(decoding: data, as: UTF8.self)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["model"] as? String == "MODEL_PRIVATE_29" && object["max_output_tokens"] as? Int == 16_384)
            #expect(object["store"] as? Bool == false && object["truncation"] as? String == "disabled")
            #expect(object["temperature"] as? Double == 0 && (object["reasoning"] as? [String: Any])?["effort"] as? String == "none")
            #expect(object["messages"] == nil && object["response_format"] == nil && object["max_tokens"] == nil)
            #expect(!raw.contains(key) && !raw.contains("SOURCE_ID_PRIVATE_29") && !raw.contains("SOURCE_DIRECTORY_PRIVATE_29"))
            if index < 3 { #expect(!raw.contains("RAW_WORK_PRIVATE_29") && !raw.contains("PREFERENCES_PRIVATE_29")) }
            else { #expect(raw.contains("RAW_WORK_PRIVATE_29") && raw.contains("PREFERENCES_PRIVATE_29")) }
        }
        #expect(await codex.scanCount == 1)
        let reportSession = try #require(flow.openWindows[.report])
        flow.send(.editBody(flow.body + "\n\n明确手工修改", day: flow.selectedDay, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.copyMarkdown); #expect(copies == [flow.body] && flow.generationSources != nil)
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        #expect(try await database.load().reports.first?.markdown == flow.body)
        let forbidden = [key, "RAW_WORK_PRIVATE_29", "SOURCE_ID_PRIVATE_29", "SOURCE_DIRECTORY_PRIVATE_29"]
        for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: file)
            #expect(forbidden.allSatisfy { data.range(of: Data($0.utf8)) == nil })
        }
        log.flushLog()
        let messages = memory.snapshot(), probes = messages.filter { $0.function == "ai_validation_finished" }
        try expectOnlyWhitelistedTelemetry(messages, forbidden: forbidden + ["PREFERENCES_PRIVATE_29", "MODEL_PRIVATE_29",
            environment.transport.endpoint.absoluteString, environment.credentialKey.base64EncodedString(), payload, flow.body])
        #expect(probes.count == 3 && probes.allSatisfy { $0.message.contains("service=responses") })
        for message in messages {
            let secrets = forbidden + ["PREFERENCES_PRIVATE_29", "MODEL_PRIVATE_29", environment.transport.endpoint.absoluteString,
                                       environment.credentialKey.base64EncodedString(), payload, flow.body]
            #expect(secrets.allSatisfy { !message.message.contains($0) && !message.messageFormat.contains($0) })
            #expect(message.file == "DailyReports" && message.line == 0 && message.context == 0 && message.representedObject == nil)
        }
        #expect(memory.logFormatter == nil)
        await database.close()
        let reopened = DailyReportDatabase(directory: environment.directory)
        let restored = try await reopened.load()
        #expect(restored.aiServices.current == .responses && restored.aiServices.configurations[.responses]?.hasMatchingValidation == true)
        #expect(restored.reports.first?.markdown == flow.body)
        #expect(restored.aiServices.configurations[.chatCompletions]?.credential == nil && restored.aiServices.configurations[.messages]?.credential == nil)
        await reopened.close()
    }
}
