import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportGenerationTests {
    @Test(arguments: ["-", "  -  ", "- \n- ", "+\n*", "1.\n2."])
    func emptyListSectionsCannotReplaceTheExistingDraftOrSources(_ emptyList: String) async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("empty-list-section")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        let original = flow.body, sourceTitles = flow.generationSources?.groups.first?.titles
        var sections = Dictionary(uniqueKeysWithValues: ReportPayload.keys.map { ($0, "") })
        sections["decisions"] = emptyList
        await environment.ai.enqueue(.success(try ReportJSON.encode(sections)))
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == .invalidResponse)
        #expect(flow.hasDraft && flow.body == original)
        #expect(flow.generationSources?.groups.first?.titles == sourceTitles)
        #expect(flow.savedAIService.hasMatchingValidation)
        #expect(await environment.ai.requests.count == 2)
    }

    @Test func aChangedConfigurationCannotBecomeActiveBeforeItCancelsTheRunningGeneration() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("config-commit-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.requestSettingsPage(.aiServices))
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest()
        let baseline = flow.savedAIService.requestBaseline
        flow.send(.requestCloseReport(try #require(flow.openWindows[.report])))
        let before = try #require(flow.confirmation)
        var edit = flow.aiServiceEdit; edit.configuration.model = "new-synthetic-model"
        await environment.credentials.holdNextOpen()
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await environment.credentials.waitUntilOpenIsHeld()
        #expect(flow.savedAIService.requestBaseline == baseline || flow.activeGenerationDay == nil)
        await environment.credentials.releaseOpen(); await flow.waitForStorage()
        #expect(flow.activeGenerationDay == nil && flow.savedAIService.configuration.model == "new-synthetic-model")
        #expect(flow.confirmation?.id != before.id && flow.confirmation?.isGenerating == false)
        await environment.ai.release(.success(syntheticReportPayload)); await flow.waitForGeneration()
        #expect(flow.body.isEmpty && flow.generationError == .cancelled)
    }

    @Test(arguments: [AIRequestError.network, .timeout, .refusal])
    func aFailedGenerationRefreshesTheOpenCloseConfirmation(_ failure: AIRequestError) async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("close-failure-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest()
        flow.send(.requestCloseReport(session)); let before = try #require(flow.confirmation)
        await environment.ai.release(.failure(failure)); await flow.waitForGeneration()
        let after = try #require(flow.confirmation)
        #expect(after.id != before.id && !after.isGenerating)
        flow.send(.confirm(before.id)); #expect(!environment.effects.contains(.closeReport(session: session)))
        flow.send(.confirm(after.id)); #expect(environment.effects.contains(.closeReport(session: session)))
    }

    @Test func clearConfigurationFailureRevokesEligibilityBeforePendingLocalWritesFinish() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("auth-failure")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(CGSize(width: 1_200, height: 900), session: try #require(flow.openWindows[.report])))
        await environment.storage.waitUntilSaveIsHeld()
        await environment.ai.enqueue(.failure(.authentication)); flow.send(.generateReport); await flow.waitForGeneration()
        #expect(!flow.canGenerateReport && flow.savedAIService.validation.status == .failed)
        #expect(flow.currentAIService == .chatCompletions && flow.body.isEmpty)
        await environment.storage.releaseSave(); await flow.waitForStorage()
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.validation.status == .failed)
    }
    @Test func tokenizerFailureStopsBeforeAnyWorkRequestAndHasNoByteFallback() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        environment.tokenizer = FailedTokenizer()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("token-failure")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == .tokenizer && !flow.hasDraft)
        #expect(await environment.ai.requests.isEmpty)
    }
    @Test func cancellationImmediatelyUnlocksTheTargetAndDiscardsLateResultsWithoutChangingSources() async throws {
        let environment = ReportFlowTestEnvironment()
        try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("cancel-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        let old = flow.body
        let source = flow.generationSources?.groups.first?.titles
        let day = flow.selectedDay, session = try #require(flow.openWindows[.report])
        await environment.ai.holdNextResponse()
        flow.send(.generateReport); await environment.ai.waitForRequest(2)
        #expect(flow.isGeneratingSelectedReport)
        flow.send(.editBody("blocked edit", day: day, session: session, revision: flow.reportEditRevision))
        #expect(flow.body == old)
        flow.send(.moveDate(1))
        flow.send(.editBody("other date handwriting", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        #expect(flow.body == "other date handwriting")
        flow.send(.generateReport)
        #expect(await environment.ai.requests.count == 2)
        flow.send(.selectReportDay(day)); flow.send(.cancelGeneration)
        #expect(!flow.isGeneratingSelectedReport && flow.activeGenerationDay == nil)
        await environment.ai.release(.success(syntheticReportPayload.replacingOccurrences(of: "合成进展", with: "late")))
        await flow.waitForGeneration()
        #expect(flow.body == old)
        #expect(flow.generationSources?.groups.first?.titles == source)
        #expect(flow.generationError == .cancelled)
        #expect(await environment.codex.scanCount == 1)
    }

    @Test func closingConfirmationKeepsRunningAndRefreshesWhenAResultCreatesADraft() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("close-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest()
        flow.send(.requestCloseReport(session))
        let before = try #require(flow.confirmation)
        #expect(before.isGenerating && flow.activeGenerationDay != nil)
        #expect(before.draftDays.isEmpty)
        await environment.ai.release(.success(syntheticReportPayload)); await flow.waitForGeneration()
        let after = try #require(flow.confirmation)
        #expect(after.id != before.id && after.draftDays == [flow.selectedDay])
        flow.send(.confirm(before.id)); #expect(flow.hasDraft)
        flow.send(.cancelConfirmation); #expect(flow.hasDraft)
        flow.send(.requestCloseReport(session)); flow.send(.confirm(try #require(flow.confirmation).id))
        #expect(!flow.hasDraft && flow.generationSources == nil)
    }

    @Test func replacingHandwritingRequiresAFreshConfirmationAndMalformedOutputPreservesIt() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("overwrite-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("original handwriting", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.generateReport); let old = try #require(flow.confirmation)
        #expect(await environment.ai.requests.isEmpty)
        flow.send(.editBody("changed handwriting", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.confirm(old.id)); #expect(await environment.ai.requests.isEmpty)
        await environment.ai.enqueue(.success("{\"overview\":\"missing five sections\"}"))
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.body == "changed handwriting" && flow.hasDraft)
        #expect(flow.generationSources == nil && flow.generationError == .invalidResponse)
        #expect(flow.savedAIService.hasMatchingValidation)
    }

    @Test func oversizedInputWaitsForPlanConfirmationAndDoesNotDiscardAnyTurn() async throws {
        let environment = ReportFlowTestEnvironment()
        try await installSyntheticAI(environment, totalBudget: 5_000, outputLimit: 1_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("large-28", user: String(repeating: "当天完整内容👩🏽‍💻", count: 2_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == nil && flow.confirmation?.generationScale?.requiresConfirmation == true)
        #expect(await environment.ai.requests.isEmpty)
        #expect(flow.confirmedSnapshot?.sessions[0].turns[0].userText.count == String(repeating: "当天完整内容👩🏽‍💻", count: 2_000).count)
    }
    @Test func auxiliaryUnitsAreWholeAndSavedHistoryDoesNotBackfillMissingDaysOrReadDrafts() async throws {
        let environment = ReportFlowTestEnvironment()
        try await installSyntheticAI(environment, totalBudget: 5_000, outputLimit: 1_000)
        var settings = DailyReportGeneralSettings(); settings.historyLookbackDays = 2
        await environment.storage.setGeneralSettings(settings)
        let today = ReportDay(date: environment.now, timeZone: TimeZone(identifier: "Etc/UTC")!)
        func prior(_ offset: Int) -> ReportDay {
            ReportDay(date: today.calendar.date(byAdding: .day, value: -offset, to: today.start)!, timeZone: today.timeZone)
        }
        try await environment.storage.save(.init(day: prior(2), markdown: "SAVED_HISTORY_USED_28", savedAt: environment.now, lastEditedAt: nil))
        try await environment.storage.save(.init(day: prior(3), markdown: "TOO_OLD_NOT_USED_28", savedAt: environment.now, lastEditedAt: nil))
        let candidate = CodexCandidateSession(id: "private-id-28", title: "Private local title 28", workDirectory: "/private/synthetic/28", origin: .user,
            turns: [CodexWorkTurn(id: "today", startedAt: environment.now, day: today, userText: "TODAY_REQUIRED_28", finalAnswer: nil)],
            background: [
                CodexWorkTurn(id: "old-small", startedAt: environment.now.addingTimeInterval(-100), day: prior(1), userText: "OLDER_BACKGROUND_28", finalAnswer: nil),
                CodexWorkTurn(id: "large", startedAt: environment.now.addingTimeInterval(-50), day: prior(1), userText: String(repeating: "LARGE_BACKGROUND_28", count: 1_000), finalAnswer: nil),
                CodexWorkTurn(id: "near", startedAt: environment.now.addingTimeInterval(-1), day: prior(1), userText: "NEAREST_BACKGROUND_28", finalAnswer: nil)
            ])
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.selectReportDay(prior(2)))
        flow.send(.editBody("HISTORY_DRAFT_MUST_NOT_SEND_28", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        flow.send(.selectReportDay(today))
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let request = try #require(await environment.ai.requests.first)
        #expect(request.input.contains("TODAY_REQUIRED_28") && request.input.contains("SAVED_HISTORY_USED_28"))
        #expect(!request.input.contains("HISTORY_DRAFT_MUST_NOT_SEND_28") && !request.input.contains("TOO_OLD_NOT_USED_28"))
        #expect(!request.input.contains("LARGE_BACKGROUND_28") && !request.input.contains("private-id-28"))
        let evidence = try #require(try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any])
        let background = try #require(evidence["background"] as? [[String: Any]])
        #expect(background.compactMap { $0["user"] as? String } == ["OLDER_BACKGROUND_28", "NEAREST_BACKGROUND_28"])
        #expect(flow.generationSources?.historyDays == [prior(2)])
        let tokenizer = OfflineReportTokenizer()
        let schemaTokens = try await tokenizer.count(ChatCompletionsAdapter.serializedFormat(try #require(request.schema)))
        let fixed = try await tokenizer.count(request.instruction) + schemaTokens + 1_024
        #expect(try await fixed + tokenizer.count(request.input) <= 3_200)
    }
    @Test func auxiliarySerializationMarkersCannotExceedTheTwentyPercentCap() async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment, outputLimit: 1_000)
        let candidate = CodexCandidateSession(id: "aux-cap", title: "local aux cap", workDirectory: nil, origin: .user,
            turns: syntheticCandidate("today").turns,
            background: [CodexWorkTurn(id: "background", startedAt: environment.now.addingTimeInterval(-1),
                day: ReportDay(date: environment.now.addingTimeInterval(-86_400), timeZone: .gmt),
                userText: "A complete synthetic background unit.", finalAnswer: nil)])
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let first = try #require(await environment.ai.requests.first)
        let evidence = try #require(try JSONSerialization.jsonObject(with: Data(first.input.utf8)) as? [String: Any])
        let units = try #require(evidence["background"] as? [[String: Any]])
        let tokenizer = OfflineReportTokenizer()
        let unit = try JSONSerialization.data(withJSONObject: try #require(units.first), options: [.sortedKeys, .withoutEscapingSlashes])
        let cost = try await tokenizer.count(String(decoding: unit, as: UTF8.self))
        let instruction = try await tokenizer.count(first.instruction)
        let schema = try await tokenizer.count(ChatCompletionsAdapter.serializedFormat(try #require(first.schema)))
        let inputLimit = instruction + schema + 1_024 + cost * 5
        let totalBudget = 1_000 + (inputLimit * 5 + 3) / 4
        flow.send(.requestSettingsPage(.aiServices))
        var edit = flow.aiServiceEdit; edit.totalBudget = String(totalBudget)
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        await environment.ai.enqueue(.success(syntheticReportPayload)); flow.send(.generateReport); await flow.waitForGeneration()
        let second = try #require(await environment.ai.requests.last)
        let constrained = try #require(try JSONSerialization.jsonObject(with: Data(second.input.utf8)) as? [String: Any])
        #expect((constrained["background"] as? [[String: Any]])?.isEmpty == true)
        #expect(second.input.contains("合成工作"))
    }

    @Test(arguments: ["outputOnly", "contextOnly", "model", "language"])
    func runtimeConfigurationRulesUseTheStartingRequestAndOnlyRequiredChangesCancel(_ change: String) async throws {
        let environment = ReportFlowTestEnvironment(); try await installSyntheticAI(environment)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("settings-28")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.holdNextResponse(); flow.send(.generateReport); await environment.ai.waitForRequest()
        let session = try #require(flow.openWindows[.settings])
        if change == "language" {
            flow.send(.requestSettingsPage(.general))
            var edit = flow.generalSettingsEdit; edit.outputLanguage = .english
            flow.send(.editGeneralSettings(edit, session: session)); flow.send(.saveGeneralSettings)
        } else {
            flow.send(.requestSettingsPage(.aiServices))
            var edit = flow.aiServiceEdit
            if change == "outputOnly" { edit.outputLimit = "16385" }
            if change == "contextOnly" { edit.totalBudget = "65537"; edit.concurrency = "1" }
            if change == "model" { edit.configuration.model = "changed-synthetic" }
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision)); flow.send(.saveAIService)
        }
        await flow.waitForStorage()
        #expect((flow.activeGenerationDay == nil) == (change == "model"))
        await environment.ai.release(.success(syntheticReportPayload)); await flow.waitForGeneration()
        if change == "model" { #expect(flow.body.isEmpty && flow.generationError == .cancelled) }
        else { #expect(flow.body.hasPrefix("## 今日概览")) }
        if change == "outputOnly" { #expect(flow.savedAIService.validation.status == .needsRevalidation) }
        if change == "contextOnly" { #expect(flow.savedAIService.hasMatchingValidation) }
        #expect(await environment.ai.requests.first?.configuration.outputLimit == 16_384)
    }

    @Test func completeGenerationUsesTheConfirmedSnapshotAndClearsItsTemporarySourcesOnlyAfterSaving() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/compose/"
        saved.configuration.model = "synthetic-compose"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_GENERATION_KEY_28")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline,
                                              checkedAt: environment.now, streaming: .unknown, structured: .supported)
        var settings = AIServiceSettings(); settings.configurations[.chatCompletions] = saved; settings.current = .chatCompletions
        await environment.storage.setAISettings(settings)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("source-28", user: "当天完成合成文档。")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        await environment.ai.enqueue(.success(#"{"overview":"合成进展","completed":"完成合成文档","deliverables":"文档","decisions":"","risks":"","plans":""}"#))
        flow.send(.generateReport)
        await flow.waitForGeneration()
        #expect(flow.hasDraft)
        #expect(flow.body.contains("## 完成事项\n\n完成合成文档"))
        #expect(flow.generationSources?.groups.first?.titles == ["合成 source-28"])
        #expect(await environment.codex.scanCount == 1)
        flow.send(.selectAllSessions(false))
        #expect(flow.generationSources?.groups.first?.titles == ["合成 source-28"])
        await environment.storage.failSaves(true)
        flow.send(.save); await flow.waitForStorage()
        #expect(flow.hasDraft && flow.generationSources != nil)
        await environment.storage.failSaves(false)
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        let requests = await environment.ai.requests
        #expect(requests.count == 1)
        #expect(requests[0].input.contains("当天完成合成文档。"))
        #expect(!requests[0].input.contains("source-28"))
        #expect(!requests[0].input.contains("/synthetic/project"))
    }
}

private nonisolated struct FailedTokenizer: ReportTokenCounting {
    func count(_ text: String) async throws -> Int { throw AIRequestError.tokenizer }
}

let syntheticReportPayload = #"{"overview":"合成进展","completed":"完成合成文档","deliverables":"文档","decisions":"","risks":"","plans":""}"#

@MainActor
func installSyntheticAI(_ environment: ReportFlowTestEnvironment, credential: String = "SYNTHETIC_GENERATION_KEY_28",
                        totalBudget: Int = 65_536, outputLimit: Int = 16_384) async throws {
    var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
    saved.configuration.endpoint = "https://example.invalid/compose/"; saved.configuration.model = "synthetic-compose"
    saved.configuration.totalBudget = totalBudget; saved.configuration.outputLimit = outputLimit
    saved.credential = try await environment.credentials.seal(credential); saved.credentialVersion = 1
    saved.validation = .init(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.now,
                             streaming: .unknown, structured: .supported)
    var settings = AIServiceSettings(); settings.configurations[.chatCompletions] = saved; settings.current = .chatCompletions
    await environment.storage.setAISettings(settings)
}
