import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct MessagesFlowTests {
    @Test func directBudgetCountsTheActualMessagesFormatAndEffortWrapperWithoutDroppingTurns() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticMessages(environment, validated: true, current: true)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("BUDGET_SOURCE_30")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let sample = try #require(await environment.ai.requests.first), original = flow.body
        let schema = try JSONSerialization.jsonObject(with: Data(ReportPayload.schema.utf8))
        let native = try JSONSerialization.data(withJSONObject: ["format": ["type": "json_schema", "schema": schema], "effort": "high"],
                                                options: [.sortedKeys, .withoutEscapingSlashes])
        let tokenizer = OfflineReportTokenizer()
        let cost = try await tokenizer.count(sample.instruction) + tokenizer.count(sample.input)
            + tokenizer.count(String(decoding: native, as: UTF8.self)) + 1_024
        let firstFittingDifference = (cost * 5 + 3) / 4
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        for fits in [false, true] {
            var edit = flow.aiServiceEdit
            edit.totalBudget = String(4_096 + firstFittingDifference - (fits ? 0 : 1))
            flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService); await flow.waitForStorage()
            if fits { await environment.ai.enqueue(.success(syntheticReportPayload)) }
            flow.send(.generateReport); await flow.waitForGeneration()
            #expect(await environment.ai.requests.count == (fits ? 2 : 1))
            #expect(flow.body == original && flow.generationSources != nil && flow.savedAIService.hasMatchingValidation)
            #expect(flow.confirmedSnapshot?.sessions.first?.turns.first?.userText == "合成工作")
            #expect(fits ? flow.generationError == nil : flow.generationError == .budget)
        }
    }

    @Test(arguments: [AIRequestError.network, .timeout, .invalidResponse, .authentication, .parameters])
    func unfinishedValidationKeepsTheOldProofAndExplicitFailuresOnlyRevokeMatchingQualification(_ failure: AIRequestError) async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticMessages(environment, validated: true, current: true)
        let flow = environment.makeFlow(); flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        let original = flow.savedAIService.validation
        await environment.ai.enqueue(.success("OK")); await environment.ai.enqueue(.failure(failure))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.currentAIService == .messages)
        #expect(await environment.ai.requests.count == 2)
        if failure.invalidatesConfiguration {
            #expect(flow.savedAIService.validation.status == .failed && flow.savedAIService.validation.streaming == .unknown)
        } else { #expect(flow.savedAIService.validation == original) }
        let baseline = flow.savedAIService.requestBaseline
        #expect(baseline.authentication == .messages(version: "2023-06-01") && baseline.store == nil && baseline.truncation == nil)
        #expect(baseline.outputLimit == 4_096 && baseline.credentialVersion == 1)
    }

    @Test func explicitlyUnsupportedOptionsUseTheFixedTextContractAndEnglishChapters() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticMessages(environment)
        var settings = DailyReportGeneralSettings(); settings.outputLanguage = .english
        await environment.storage.setGeneralSettings(settings)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("PLAIN_SOURCE_30")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        await environment.ai.enqueue(.success("OK")); await environment.ai.enqueue(.failure(.streamingUnsupported))
        await environment.ai.enqueue(.failure(.structuredUnsupported))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.savedAIService.validation.streaming == .unsupported
                && flow.savedAIService.validation.structured == .unsupported && flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        await environment.ai.enqueue(.success(#"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#))
        flow.send(.generateReport); await flow.waitForGeneration()
        let request = try #require(await environment.ai.requests.last)
        #expect(!request.streaming && request.schema == nil)
        #expect(flow.body.hasPrefix("## Today’s Overview\n\nNo confirmed content") && flow.body.contains("## Tomorrow’s Plan\n\nNo confirmed content"))
    }

    @Test func cancellingMessagesPreservesTheDraftAndRejectsItsLateResult() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticMessages(environment, validated: true, current: true)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("CANCEL_SOURCE_30")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let original = flow.body, titles = flow.generationSources?.groups.first?.titles
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest(2)
        flow.send(.cancelGeneration)
        #expect(flow.activeGenerationDay == nil && flow.generationError == .cancelled)
        await environment.ai.release(.success(syntheticReportPayload.replacingOccurrences(of: "合成进展", with: "LATE_30")))
        await flow.waitForGeneration()
        #expect(flow.body == original && flow.generationSources?.groups.first?.titles == titles)
        #expect(await environment.codex.scanCount == 1)
    }

    @Test func leavingDuringValidationCancelsAndCannotCommitALateProof() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticMessages(environment)
        let flow = environment.makeFlow(); flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        let original = flow.savedAIService, session = try #require(flow.openWindows[.settings])
        await environment.ai.holdNextResponse(); flow.send(.requestAIValidation); await environment.ai.waitForRequest()
        var edit = flow.aiServiceEdit; edit.configuration.model = "FORBIDDEN_WHILE_TESTING_30"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        #expect(!flow.hasAIServiceEdits)
        flow.send(.requestSettingsPage(.general)); flow.send(.cancelConfirmation)
        #expect(flow.isValidatingAIService && flow.settingsPage == .aiServices)
        flow.send(.requestSettingsPage(.general)); flow.send(.confirm(try #require(flow.confirmation).id))
        #expect(!flow.isValidatingAIService && flow.settingsPage == .general)
        await environment.ai.release(.success("OK")); await flow.waitForAIValidation()
        #expect(flow.savedAIService == original)
        #expect(await environment.ai.requests.count == 1)
        #expect(try await environment.storage.load().aiServices.configurations[.messages] == original)
    }

    @Test func explicitMessagesValidationSelectionGenerationEditingAndSavingShareTheFlow() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let originalChat = try await environment.storage.load().aiServices.configurations[.chatCompletions]
        try await installSyntheticMessages(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("SOURCE_PRIVATE_30", user: "当天完成合成文档。")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.messages))
        #expect(await environment.ai.requests.isEmpty)
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.currentAIService == .chatCompletions)
        #expect(environment.aiValidationEvents.count == 3 && environment.aiValidationEvents.allSatisfy { $0.service == .messages })
        guard flow.savedAIService.hasMatchingValidation else { return }
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.currentAIService == .messages && flow.body.contains("## 完成事项\n\n完成合成文档"))
        #expect(flow.generationSources?.groups.first?.titles == ["合成 SOURCE_PRIVATE_30"])
        let requests = await environment.ai.requests
        #expect(requests.count == 4 && requests.allSatisfy { $0.configuration.service == .messages && $0.credential == "SYNTHETIC_FLOW_KEY_30" })
        #expect(requests.prefix(3).allSatisfy { !$0.input.contains("当天完成合成文档") && $0.configuration.outputLimit == 4_096 })
        #expect(requests.last?.schema == ReportPayload.schema && requests.last?.streaming == true)
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody(flow.body + "\n\n明确手工修改", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        #expect(flow.generationSources != nil)
        await environment.storage.failSaves(true); flow.send(.save); await flow.waitForStorage()
        #expect(flow.hasDraft && flow.generationSources != nil)
        await environment.storage.failSaves(false); flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        #expect(try await environment.storage.load().reports.first?.markdown == flow.body)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == originalChat)
        #expect(await environment.codex.scanCount == 1)
    }
}

@MainActor
func installSyntheticMessages(_ environment: ReportFlowTestEnvironment, validated: Bool = false, current: Bool = false) async throws {
    var settings = try await environment.storage.load().aiServices
    var saved = SavedAIService(configuration: AIServiceConfiguration(service: .messages))
    saved.configuration.endpoint = "https://example.invalid/messages/final/?probe=30"
    saved.configuration.model = "synthetic-messages-30"
    saved.configuration.defaults = .messages(.init(temperature: 0, thinking: .adaptive, effort: .high))
    saved.configuration.outputLimit = 4_096
    saved.credential = try await environment.credentials.seal("SYNTHETIC_FLOW_KEY_30"); saved.credentialVersion = 1
    if validated {
        saved.validation = .init(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.now,
                                 streaming: .supported, structured: .supported)
    }
    settings.configurations[.messages] = saved
    if current { settings.current = .messages }
    await environment.storage.setAISettings(settings)
}
