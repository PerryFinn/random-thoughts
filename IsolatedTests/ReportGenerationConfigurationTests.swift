import Foundation
import Testing
@testable import random_thoughts

@MainActor
@Suite(.serialized)
struct ReportGenerationConfigurationTests {
    @Test(arguments: [ReportGenerationStage.composing, .extracting, .merging],
          ["endpoint", "model", "defaults", "credential", "deleteCredential", "current"])
    func committedRequestChangesCancelAllRemainingStages(_ stage: ReportGenerationStage, _ change: String) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: stage == .merging ? .dense : .compact)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        try await installSyntheticResponses(environment, validated: true)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: stage != .composing)
        let body = flow.body, sources = flow.generationSources?.groups.first?.titles
        await access.hold(stage: stage)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: stage)
        flow.send(.requestSettingsPage(.aiServices))
        if change == "deleteCredential" {
            flow.send(.requestDeleteAICredential); flow.send(.confirm(try #require(flow.confirmation).id))
        } else if change == "current" {
            flow.send(.selectAIServiceType(.responses)); flow.send(.makeAIServiceCurrent)
        } else {
            var edit = flow.aiServiceEdit
            switch change {
            case "endpoint": edit.configuration.endpoint += "?changed=32"
            case "model": edit.configuration.model = "changed-model-32"
            case "defaults": edit.temperature = "0"
            default: edit.newCredential = "SYNTHETIC_REPLACEMENT_KEY_32"
            }
            flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
        }
        await flow.waitForStorage()
        #expect(flow.activeGenerationDay == nil)
        if flow.activeGenerationDay != nil { await access.releaseAll() }
        let count = await access.requests.count
        await flow.waitForGeneration()
        #expect(flow.activeGenerationDay == nil && flow.generationError == .cancelled)
        #expect(flow.body == body && flow.generationSources?.groups.first?.titles == sources)
        #expect(await access.requests.count == count)
        #expect(flow.currentAIService == (change == "current" ? .responses : .chatCompletions))
    }

    @Test(arguments: [AIRequestError.authentication, .model, .parameters, .network])
    func oldOutputBaselineFailuresCannotRevokeANewlyValidatedBaseline(_ failure: AIRequestError) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: true)
        let body = flow.body, sources = flow.generationSources?.groups.first?.titles
        await access.hold(stage: .extracting)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: .extracting)
        let firstWork = 1
        flow.send(.requestSettingsPage(.aiServices))
        var edit = flow.aiServiceEdit; edit.outputLimit = "3500"
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.activeGenerationDay != nil && flow.savedAIService.validation.status == .needsRevalidation)
        let beforeValidation = await access.requests.count
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        let proof = flow.savedAIService.validation
        let afterValidation = await access.requests.count
        #expect(flow.savedAIService.hasMatchingValidation && afterValidation == beforeValidation + 3)
        await access.release(firstWork, failure: failure); await flow.waitForGeneration(); await flow.waitForStorage()
        #expect(flow.generationError == failure && flow.savedAIService.validation == proof)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.validation == proof)
        #expect(flow.body == body && flow.generationSources?.groups.first?.titles == sources)
        #expect(flow.currentAIService == .chatCompletions && flow.canGenerateReport)
        let requests = await access.requests
        #expect(requests.allSatisfy { if case .probe = $0.intent { $0.configuration.outputLimit == 3_500 } else { $0.configuration.outputLimit == 3_000 } })
    }

    @Test func aFailedConfigurationCommitPreservesTheRunningRequestAndOldConfiguration() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: false)
        let old = flow.savedAIService
        await access.hold(stage: .composing)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: .composing)
        await environment.storage.failSaves(true)
        flow.send(.requestSettingsPage(.aiServices))
        var edit = flow.aiServiceEdit; edit.configuration.model = "uncommitted-model-32"
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.savedAIService == old && flow.activeGenerationDay != nil && flow.hasAIServiceEdits)
        await access.releaseAll(); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationError == nil)
        #expect(await access.requests.allSatisfy { $0.configuration == old.configuration })
    }

    @Test(arguments: [false, true])
    func pendingPlansRequireFreshApprovalForChangedSourcesAndSavedHistory(_ historyChange: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: true)
        flow.send(.generateReport); await flow.waitForGeneration()
        let before = try #require(flow.confirmation), day = flow.selectedDay
        if historyChange {
            flow.send(.moveDate(-1))
            flow.send(.editBody("NEW_PENDING_HISTORY_32", day: flow.selectedDay,
                session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
            flow.send(.save); await flow.waitForStorage(); flow.send(.selectReportDay(day))
            flow.send(.generateReport)
        } else {
            await environment.codex.setScan(.init(sessions: [syntheticCandidate("changed-pending-source-32",
                user: "NEW_PENDING_SOURCE_32")], failures: [], version: nil))
            flow.send(.scanSessions); await flow.waitForSessionScan()
            flow.send(.moveDate(-1)); flow.send(.selectReportDay(day))
            flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
            flow.send(.generateReport)
        }
        let pending = try #require(flow.confirmation), count = await access.requests.count
        flow.send(.confirm(pending.id)); await flow.waitForGeneration()
        let refreshed = try #require(flow.confirmation)
        #expect(refreshed.id != pending.id && refreshed.generationContext != before.generationContext)
        #expect(await access.requests.count == count)
        flow.send(.confirm(before.id)); #expect(await access.requests.count == count)
        flow.send(.confirm(refreshed.id)); await flow.waitForGeneration()
        #expect(flow.generationError == nil)
        #expect(await access.requests.last?.input.contains(historyChange ? "NEW_PENDING_HISTORY_32" : "NEW_PENDING_SOURCE_32") == true)
        #expect(await environment.codex.scanCount == (historyChange ? 2 : 3))
    }

    @Test(arguments: ["context", "output", "concurrency", "language", "preferences", "lookback"])
    func pendingPlansRequireFreshApprovalForSavedSettings(_ change: String) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: true)
        flow.send(.generateReport); await flow.waitForGeneration()
        let before = try #require(flow.confirmation)
        let session = try #require(flow.openWindows[.settings])
        if ["language", "preferences", "lookback"].contains(change) {
            flow.send(.requestSettingsPage(.general))
            var edit = flow.generalSettingsEdit
            if change == "language" { edit.outputLanguage = .english }
            if change == "preferences" { edit.generationPreferences = "NEW_CONFIRMED_PREFERENCE_32" }
            if change == "lookback" { edit.historyLookbackDays = 0 }
            flow.send(.editGeneralSettings(edit, session: session)); flow.send(.saveGeneralSettings)
        } else {
            flow.send(.requestSettingsPage(.aiServices))
            var edit = flow.aiServiceEdit
            if change == "context" { edit.totalBudget = "13000" }
            if change == "output" { edit.outputLimit = "3500" }
            if change == "concurrency" { edit.concurrency = "1" }
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision)); flow.send(.saveAIService)
        }
        await flow.waitForStorage()
        if change == "output" { flow.send(.requestAIValidation); await flow.waitForAIValidation() }
        let requests = await access.requests.count
        flow.send(.confirm(before.id)); await flow.waitForGeneration()
        let after = try #require(flow.confirmation)
        #expect(after.id != before.id && after.generationContext != before.generationContext)
        #expect(await access.requests.count == requests)
        flow.send(.confirm(before.id)); #expect(await access.requests.count == requests)
        flow.send(.confirm(after.id)); await flow.waitForGeneration()
        #expect(flow.generationError == nil && flow.hasDraft)
        #expect(await access.requests.last?.configuration == flow.savedAIService.configuration)
        #expect(await environment.codex.scanCount == 2)
    }
}

@MainActor
func prepareGeneratedLifecycleFlow(_ environment: ReportFlowTestEnvironment, batched: Bool) async throws -> DailyReportFlow {
    let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("original-source-32")])
    flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
    flow.send(.generateReport); await flow.waitForGeneration()
    _ = try #require(flow.generationSources)
    if batched {
        await environment.codex.setScan(.init(sessions: [syntheticCandidate("new-source-32",
            user: String(repeating: " evidence", count: 60_000))], failures: [], version: nil))
        flow.send(.scanSessions); await flow.waitForSessionScan()
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
    }
    return flow
}

@MainActor
func beginHeldLifecycleGeneration(_ flow: DailyReportFlow, access: BatchAIService, stage: ReportGenerationStage) async throws {
    let before = await access.requests.count
    flow.send(.generateReport)
    if stage != .composing {
        await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id))
    }
    let target = stage == .composing ? 1 : stage == .extracting ? 3 : try #require(flow.generationScale).extractionRequests + 1
    await access.waitForRequests(before + target)
    #expect(flow.generationStage == stage)
}
