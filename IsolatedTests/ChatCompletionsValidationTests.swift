import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ChatCompletionsValidationTests {
    @Test func leavingCanContinueOrCancelAndLateProbeCallbacksCannotChangeTheSavedConclusion() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = environment.makeFlow()
        flow.send(.open(.settings)); await flow.waitForStorage(); flow.send(.requestSettingsPage(.aiServices))
        let saved = flow.savedAIService, session = try #require(flow.openWindows[.settings])
        await environment.ai.holdNextResponse(); flow.send(.requestAIValidation); await environment.ai.waitForRequest()
        var edit = flow.aiServiceEdit; edit.configuration.model = "forbidden-edit-while-testing"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        #expect(!flow.hasAIServiceEdits)
        flow.send(.requestDeleteAICredential); #expect(flow.confirmation == nil)
        flow.send(.requestSettingsPage(.general)); #expect(flow.confirmation != nil && flow.isValidatingAIService)
        flow.send(.cancelConfirmation); #expect(flow.isValidatingAIService && flow.settingsPage == .aiServices)
        flow.send(.requestSettingsPage(.general)); flow.send(.confirm(try #require(flow.confirmation).id))
        #expect(!flow.isValidatingAIService && flow.settingsPage == .general)
        await environment.ai.release(.success("OK")); await flow.waitForAIValidation()
        #expect(flow.savedAIService == saved)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == saved)
        #expect(await environment.ai.requests.count == 1)
    }

    @Test func cancellingBeforeProofCommitDoesNotOverwriteANewlySavedConfiguration() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = environment.makeFlow()
        flow.send(.open(.settings)); await flow.waitForStorage(); flow.send(.requestSettingsPage(.aiServices))
        await environment.storage.holdNextSave(); flow.send(.requestAIValidation)
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.cancelAIValidation)
        var edit = flow.aiServiceEdit; edit.configuration.model = "new-baseline-28"
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        await environment.storage.releaseSave(); await flow.waitForAIValidation()
        #expect(flow.savedAIService.configuration.model == "new-baseline-28")
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == flow.savedAIService)
    }
    @Test(arguments: [AIRequestError.authentication, .network])
    func optionalProbeFailureCannotOverwriteTheOldConclusion(_ failure: AIRequestError) async throws {
        let environment = ReportFlowTestEnvironment()
        var settings = AIServiceSettings()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/probe"
        saved.configuration.model = "synthetic"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_PROBE_KEY_28")
        saved.validation = .init(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.now,
                                 streaming: .supported, structured: .supported)
        settings.configurations[.chatCompletions] = saved
        settings.current = .chatCompletions
        await environment.storage.setAISettings(settings)
        await environment.ai.enqueue(.success("OK"))
        await environment.ai.enqueue(.failure(failure))
        let flow = environment.makeFlow()
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.requestAIValidation)
        await flow.waitForAIValidation()
        #expect(flow.currentAIService == .chatCompletions)
        if failure == .authentication {
            #expect(flow.savedAIService.validation.status == .failed)
            #expect(await environment.ai.requests.count == 2)
        } else {
            #expect(flow.savedAIService.validation == saved.validation)
        }
    }

    @Test func databaseProofWriteDoesNotOverwriteAChangedRequestBaseline() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let snapshot = try await database.load()
        let old = snapshot.aiServices.configurations[.chatCompletions]!
        var changed = old
        changed.configuration.model = "changed-synthetic-model"
        try await database.saveAIService(changed)
        let proof = AIServiceValidation(status: .validated, baseline: old.requestBaseline, checkedAt: environment.clock.now)
        #expect(try await !database.saveAIValidation(proof, matching: old.requestBaseline))
        #expect(try await database.load().aiServices.configurations[.chatCompletions] == changed)
    }
    @Test func optionalCapabilityRejectionsAreIndependentAndCannotCauseParameterFallback() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/synthetic-chat/"
        saved.configuration.model = "synthetic-chat"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_PROBE_KEY_28")
        var settings = AIServiceSettings(); settings.configurations[.chatCompletions] = saved
        await environment.storage.setAISettings(settings)
        await environment.ai.enqueue(.success("OK"))
        await environment.ai.enqueue(.failure(.streamingUnsupported))
        await environment.ai.enqueue(.failure(.structuredUnsupported))
        let flow = environment.makeFlow()
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.requestAIValidation)
        await flow.waitForAIValidation()
        #expect(flow.savedAIService.validation.status == .validated)
        #expect(flow.savedAIService.validation.streaming == .unsupported)
        #expect(flow.savedAIService.validation.structured == .unsupported)
        let requests = await environment.ai.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.configuration.outputLimit == saved.configuration.outputLimit })
        #expect(requests.allSatisfy { !$0.input.contains("preference") && $0.credential == "SYNTHETIC_PROBE_KEY_28" })
    }
    @Test func explicitSavedConfigurationValidationDoesNotAutomaticallySelectCurrentService() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/synthetic-chat/"
        saved.configuration.model = "synthetic-chat"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_PROBE_KEY_28")
        saved.credentialVersion = 1
        var settings = AIServiceSettings()
        settings.configurations[.chatCompletions] = saved
        await environment.storage.setAISettings(settings)
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices))
        flow.send(.requestAIValidation)
        await flow.waitForAIValidation()
        #expect(flow.savedAIService.validation.status == .validated)
        #expect(flow.currentAIService == nil)
    }
}
