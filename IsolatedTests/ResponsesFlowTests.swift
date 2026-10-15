import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ResponsesFlowTests {
    @Test func directBudgetBoundaryUsesTheNativeResponsesSchemaAndRetainsEveryTurn() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticResponses(environment, validated: true, current: true)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("BUDGET_SOURCE_29")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let sample = try #require(await environment.ai.requests.first), original = flow.body
        let schema = try JSONSerialization.jsonObject(with: Data(ReportPayload.schema.utf8))
        let native = try JSONSerialization.data(withJSONObject: ["format": ["type": "json_schema", "name": "daily_report", "strict": true, "schema": schema]],
                                                options: [.sortedKeys, .withoutEscapingSlashes])
        let tokenizer = OfflineReportTokenizer()
        let cost = try await tokenizer.count(sample.instruction) + tokenizer.count(sample.input)
            + tokenizer.count(String(decoding: native, as: UTF8.self)) + 1_024
        // The independently counted native wire text must fit I=floor(4*(C-O)/5).
        let firstFittingDifference = (cost * 5 + 3) / 4
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        for fits in [false, true] {
            var edit = flow.aiServiceEdit
            edit.totalBudget = String(4_096 + firstFittingDifference - (fits ? 0 : 1))
            flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService); await flow.waitForStorage()
            if fits { await environment.ai.enqueue(.success(syntheticReportPayload)) }
            flow.send(.generateReport); await flow.waitForGeneration()
            #expect(await environment.ai.requests.count == (fits ? 2 : 1))
            #expect(flow.body == original && flow.generationSources != nil)
            #expect(flow.confirmedSnapshot?.sessions.first?.turns.first?.userText == "合成工作")
            #expect(flow.savedAIService.hasMatchingValidation)
            #expect(fits ? flow.generationError == nil : flow.generationError == .needsBatching)
        }
    }

    @Test(arguments: [AIRequestError.network, .authentication, .parameters])
    func revalidationPreservesTemporaryFailuresButRevokesOnlyExplicitConfigurationFailures(_ failure: AIRequestError) async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticResponses(environment, validated: true, current: true)
        let flow = environment.makeFlow(); flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        let previous = flow.savedAIService.validation
        await environment.ai.enqueue(.success("OK")); await environment.ai.enqueue(.failure(failure))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.currentAIService == .responses)
        #expect(await environment.ai.requests.count == 2)
        if failure == .network { #expect(flow.savedAIService.validation == previous) }
        else { #expect(flow.savedAIService.validation.status == .failed && flow.savedAIService.validation.streaming == .unknown) }
        #expect(environment.aiValidationEvents.allSatisfy { $0.service == .responses })
    }

    @Test func explicitlyUnsupportedCapabilitiesUseTheFixedTextContractAndEnglishTemplate() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticResponses(environment)
        var settings = DailyReportGeneralSettings(); settings.outputLanguage = .english
        await environment.storage.setGeneralSettings(settings)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("plain-29")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        await environment.ai.enqueue(.success("OK")); await environment.ai.enqueue(.failure(.streamingUnsupported))
        await environment.ai.enqueue(.failure(.structuredUnsupported))
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.savedAIService.validation.streaming == .unsupported
                && flow.savedAIService.validation.structured == .unsupported)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        await environment.ai.enqueue(.success(#"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#))
        flow.send(.generateReport); await flow.waitForGeneration()
        let request = try #require(await environment.ai.requests.last)
        #expect(!request.streaming && request.schema == nil)
        #expect(flow.body.hasPrefix("## Today’s Overview\n\nNo confirmed content"))
        #expect(flow.body.contains("## Tomorrow’s Plan\n\nNo confirmed content") && flow.hasDraft)
    }

    @Test func cancellingResponsesGenerationPreservesTheDraftAndRejectsItsLateResult() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticResponses(environment, validated: true, current: true)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("cancel-29")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let original = flow.body, titles = flow.generationSources?.groups.first?.titles
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest(2)
        flow.send(.cancelGeneration)
        #expect(flow.activeGenerationDay == nil && flow.generationError == .cancelled)
        await environment.ai.release(.success(syntheticReportPayload.replacingOccurrences(of: "合成进展", with: "late")))
        await flow.waitForGeneration()
        #expect(flow.body == original && flow.generationSources?.groups.first?.titles == titles)
        #expect(await environment.codex.scanCount == 1)
    }

    @Test func explicitResponsesValidationSelectionGenerationAndSavingShareTheExistingFlow() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let originalChat = try await environment.storage.load().aiServices.configurations[.chatCompletions]
        try await installSyntheticResponses(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("SOURCE_PRIVATE_29", user: "当天完成合成文档。")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(.responses))
        #expect(await environment.ai.requests.isEmpty)
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.currentAIService == .chatCompletions)
        #expect(environment.aiValidationEvents.count == 3 && environment.aiValidationEvents.allSatisfy { $0.service == .responses })
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        #expect(flow.currentAIService == .responses)
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.body.contains("## 完成事项\n\n完成合成文档"))
        #expect(flow.generationSources?.groups.first?.titles == ["合成 SOURCE_PRIVATE_29"])
        let requests = await environment.ai.requests
        #expect(requests.count == 4 && requests.allSatisfy { $0.configuration.service == .responses })
        #expect(requests.allSatisfy { $0.credential == "SYNTHETIC_FLOW_KEY_29" && $0.configuration.outputLimit == 4_096 })
        #expect(requests.prefix(3).allSatisfy { !$0.input.contains("当天完成合成文档") && !$0.instruction.contains("preferences") })
        #expect(requests.last?.schema == ReportPayload.schema && requests.last?.streaming == true)
        #expect(requests.last?.input.contains("SOURCE_PRIVATE_29") == false)
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
func installSyntheticResponses(_ environment: ReportFlowTestEnvironment, validated: Bool = false, current: Bool = false,
                               totalBudget: Int = 65_536, outputLimit: Int = 4_096) async throws {
    var settings = try await environment.storage.load().aiServices
    var saved = SavedAIService(configuration: AIServiceConfiguration(service: .responses))
    saved.configuration.endpoint = "https://example.invalid/responses/final/?probe=29"
    saved.configuration.model = "synthetic-responses-29"
    saved.configuration.defaults = .responses(.init(temperature: 0, reasoningEffort: AIReasoningEffort.none))
    saved.configuration.totalBudget = totalBudget; saved.configuration.outputLimit = outputLimit
    saved.credential = try await environment.credentials.seal("SYNTHETIC_FLOW_KEY_29"); saved.credentialVersion = 1
    if validated {
        saved.validation = .init(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.now,
                                 streaming: .supported, structured: .supported)
    }
    settings.configurations[.responses] = saved
    if current { settings.current = .responses }
    await environment.storage.setAISettings(settings)
}
