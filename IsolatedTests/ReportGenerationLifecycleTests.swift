import Foundation
import Testing
@testable import random_thoughts

@MainActor
@Suite(.serialized)
struct ReportGenerationLifecycleTests {
    @Test func knownNetworkAndTemporaryFailuresHaveDistinctActionableMessagesFromUnknownFailures() {
        #expect(AIRequestError.network.message.contains("网络"))
        #expect(AIRequestError.unavailable.message.contains("暂时"))
        #expect(AIRequestError.unknown.message.contains("未知"))
        #expect(Set([AIRequestError.network.message, AIRequestError.unavailable.message, AIRequestError.unknown.message]).count == 3)
        #expect(AIRequestError.redirect.message.contains("保留"))
    }

    @Test(arguments: [false, true])
    func cancellingAtTheCompositionBoundaryCannotDispatchAnotherRequest(_ batched: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("cancel-boundary-32",
            user: batched ? String(repeating: " evidence", count: 40_000) : "合成当天工作")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.editBody("保留原稿", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        environment.onGenerationEvent = { [weak flow] event in
            if event.kind == .stageChanged, event.stage == .composing { flow?.send(.cancelGeneration) }
        }
        flow.send(.generateReport); flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        if let confirmation = flow.confirmation { flow.send(.confirm(confirmation.id)); await flow.waitForGeneration() }
        #expect(flow.activeGenerationDay == nil && flow.generationError == .cancelled)
        #expect(flow.body == "保留原稿" && flow.generationSources == nil)
        #expect(await access.requests.allSatisfy { if case .extractFacts = $0.intent { true } else { false } })
        #expect(environment.generationEvents.last?.result == .cancelled)
    }

    @Test(arguments: [ReportGenerationStage.composing, .extracting, .merging],
          [AIRequestError.authentication, .model, .parameters, .network, .timeout, .rateLimit, .quota, .contextLimit, .invalidResponse, .unknown])
    func necessaryFailuresKeepTheWholeDraftAndOnlyExplicitConfigurationEvidenceRevokesQualification(
        _ stage: ReportGenerationStage, _ failure: AIRequestError
    ) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: stage == .merging ? .dense : .compact)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: stage != .composing)
        let body = flow.body, sources = flow.generationSources?.groups.first?.titles
        await access.hold(stage: stage)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: stage)
        let requests = await access.requests
        let failed = stage == .merging ? try #require(requests.firstIndex {
            if case .mergeFacts = $0.intent { true } else { false }
        }) : 1
        await access.release(failed, failure: failure); await flow.waitForGeneration(); await flow.waitForStorage()
        #expect(flow.generationError == failure && flow.generationRetryAt == nil && flow.activeGenerationDay == nil)
        #expect(flow.body == body && flow.generationSources?.groups.first?.titles == sources)
        #expect(flow.currentAIService == .chatCompletions)
        #expect(flow.savedAIService.hasMatchingValidation == ![.authentication, .model, .parameters].contains(failure))
        let count = await access.requests.count
        flow.send(.systemSleep); flow.send(.systemWake); flow.send(.open(.report))
        #expect(await access.requests.count == count)
        #expect(environment.generationEvents.last?.result == .failure)
    }

    @Test(arguments: [ReportGenerationStage.composing, .extracting, .merging], [false, true])
    func cancellationRejectsLateSuccessAndFailureEvenWhenTheAdapterIgnoresCancellation(_ stage: ReportGenerationStage, _ failing: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: stage == .merging ? .dense : .compact, ignoresCancellation: true)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: stage != .composing)
        let sources = flow.generationSources?.groups.first?.titles
        await access.hold(stage: stage)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: stage)
        flow.send(.cancelGeneration)
        #expect(flow.activeGenerationDay == nil && flow.confirmation == nil)
        flow.send(.editBody("取消后继续编辑", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        if failing {
            let requests = await access.requests
            for index in requests.indices.dropFirst() { await access.release(index, failure: .authentication) }
        }
        await access.releaseAll(); await flow.waitForGeneration(); await flow.waitForStorage()
        #expect(flow.body == "取消后继续编辑" && flow.generationSources?.groups.first?.titles == sources)
        #expect(flow.generationError == .cancelled && flow.savedAIService.hasMatchingValidation)
        #expect(environment.generationEvents.last?.result == .cancelled)
    }

    @Test(arguments: [false, true])
    func closingOrQuittingMergesAllDraftsAndRequiresNewApprovalAfterConcurrentCompletion(_ quitting: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .dense)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: true)
        let day = flow.selectedDay, session = try #require(flow.openWindows[.report])
        flow.send(.moveDate(1))
        flow.send(.editBody("另一个报告日的手写草稿", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        let otherDay = flow.selectedDay
        flow.send(.selectReportDay(day))
        await access.hold(stage: .merging)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: .merging)
        flow.send(quitting ? .quit : .requestCloseReport(session))
        let before = try #require(flow.confirmation)
        #expect(before.isGenerating && Set(before.draftDays) == [day, otherDay])
        await access.releaseAll(); await flow.waitForGeneration()
        let after = try #require(flow.confirmation)
        #expect(after.id != before.id && !after.isGenerating && Set(after.draftDays) == [day, otherDay])
        flow.send(.confirm(before.id)); #expect(flow.draftDays.count == 2)
        #expect(!environment.effects.contains(.quit) && !environment.effects.contains(.closeReport(session: session)))
        flow.send(.cancelConfirmation); #expect(flow.draftDays.count == 2)
        flow.send(quitting ? .quit : .requestCloseReport(session))
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.draftDays.isEmpty && flow.generationSources == nil)
        #expect(environment.effects.contains(quitting ? .quit : .closeReport(session: session)))
        #expect(try await environment.storage.load().reports.isEmpty)
    }

    @Test(arguments: [false, true])
    func sourceChangesPreserveFixedGenerationWhileEffectiveTimeZoneChangesCancelIt(_ timeZoneChange: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .dense)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: true)
        let originalDay = flow.selectedDay
        await access.hold(stage: .merging)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: .merging)
        let count = await access.requests.count
        environment.now += 3_600
        flow.send(.systemSleep); flow.send(.systemWake); flow.send(.open(.report))
        #expect(flow.activeGenerationDay == originalDay && flow.generationError == nil)
        #expect(await access.requests.count == count)
        if timeZoneChange {
            flow.send(.systemTimeZoneChanged(try #require(TimeZone(identifier: "Asia/Shanghai"))))
            #expect(flow.activeGenerationDay == nil && !flow.draftDays.contains(originalDay))
        } else {
            flow.send(.requestSettingsPage(.dataSource))
            var edit = flow.codexSourceEdit; edit.explicitDirectory = "/synthetic/new-source-32"
            flow.send(.editCodexSource(edit, session: try #require(flow.openWindows[.settings])))
            flow.send(.saveCodexSource); await flow.waitForStorage(); await flow.waitForCodexCheck()
            #expect(flow.activeGenerationDay == originalDay)
        }
        await access.releaseAll(); await flow.waitForGeneration(); await flow.waitForSessionScan()
        if timeZoneChange { #expect(flow.draftDays.isEmpty && flow.generationSources == nil) }
        else { #expect(flow.generationError == nil && flow.generationSources?.groups.first?.titles == ["合成 new-source-32"]) }
    }

    @Test func reliableWaitEndsWithManualRetryUsingLatestSettingsHistoryAndTheConfirmedSnapshot() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("retry-32")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let body = flow.body, day = flow.selectedDay
        await environment.ai.enqueueFailure(.init(reason: .rateLimit, retryAt: environment.now.addingTimeInterval(60)))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == .rateLimit && !flow.canGenerateReport && flow.body == body)
        let count = await environment.ai.requests.count
        environment.now += 59
        flow.send(.generateReport); flow.send(.systemSleep); flow.send(.systemWake); flow.send(.open(.report))
        #expect(await environment.ai.requests.count == count)
        #expect(!flow.canGenerateReport)
        environment.now += 1
        #expect(flow.canGenerateReport)
        #expect(await environment.ai.requests.count == count)
        flow.send(.requestSettingsPage(.general))
        var edit = flow.generalSettingsEdit; edit.outputLanguage = .english; edit.generationPreferences = "LATEST_RETRY_PREFERENCE_32"
        flow.send(.editGeneralSettings(edit, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.moveDate(-1))
        let yesterday = flow.selectedDay
        flow.send(.editBody("LATEST_SAVED_HISTORY_32", day: yesterday, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        flow.send(.save); await flow.waitForStorage(); flow.send(.selectReportDay(day))
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        let request = try #require(await environment.ai.requests.last)
        #expect(request.instruction.contains("LATEST_RETRY_PREFERENCE_32") && request.input.contains("LATEST_SAVED_HISTORY_32"))
        #expect(flow.body.hasPrefix("## Today’s Overview") && flow.generationRetryAt == nil)
        #expect(flow.generationSources?.historyDays == [yesterday])
        #expect(await environment.codex.scanCount == 1)
    }
}
