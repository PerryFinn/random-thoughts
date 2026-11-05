import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportBatchGenerationTests {
    @Test func explicitlyIrrelevantTinyTurnsCanConvergeWithoutCarryingUnneededTurnLists() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .noRelevant)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 500)
        let day = ReportDay(date: environment.now, timeZone: .gmt)
        let candidate = CodexCandidateSession(id: "no-relevant-31", title: "合成无团队相关内容", workDirectory: nil, origin: .user,
            turns: (0..<500).map { .init(id: "turn-\($0)", startedAt: environment.now, day: day, userText: "你好", finalAnswer: nil) }, background: [])
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        if let confirmation = flow.confirmation { flow.send(.confirm(confirmation.id)); await flow.waitForGeneration() }
        #expect(flow.hasDraft && flow.generationError == nil)
        #expect(flow.body.components(separatedBy: "无明确内容").count == 7)
        #expect(environment.generationEvents.last?.result == .success)
    }

    @Test func anUnreducedMergeFailsWithoutAnotherLayerOrRepairRequest() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .unreduced)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("no-reduction-31",
            user: String(repeating: " evidence", count: 60_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.generationError == .budget && !flow.hasDraft)
        #expect(await access.requests.contains { if case .mergeFacts = $0.intent { true } else { false } })
        #expect(await access.requests.allSatisfy { if case .composeReport = $0.intent { false } else { true } })
    }

    @Test func anImpossibleVisibleContractFailsLocallyBeforeTheFirstRequest() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 1)
        let text = String(repeating: "完整保留当天内容。", count: 2_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("impossible-31", user: text)])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == .budget && flow.confirmation == nil)
        #expect(await access.requests.isEmpty)
        #expect(flow.confirmedSnapshot?.sessions[0].turns[0].userText == text)
    }

    @Test func packingPrefersAWholeSessionBeforeSplittingItsTurnsAcrossBatches() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let day = ReportDay(date: environment.now, timeZone: .gmt)
        let second = CodexCandidateSession(id: "two-turns", title: "第二个完整会话", workDirectory: nil, origin: .user,
            turns: (0..<2).map { .init(id: "turn-\($0)", startedAt: environment.now, day: day,
                userText: String(repeating: " evidence", count: 2_500), finalAnswer: nil) }, background: [])
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("first", user: String(repeating: " evidence", count: 1_000)), second])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        let requests = await access.requests
        var sessions: [[Int]] = []
        for request in requests {
            if case .extractFacts = request.intent {
                let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
                sessions.append((input["fragments"] as! [[String: Any]]).map { $0["session"] as! Int })
            }
        }
        #expect(sessions == [[1], [2, 2]])
        #expect(flow.hasDraft)
    }
    @Test func fourRequestsRunDirectlyButFiveOrAnUncertainFourRequireConfirmation() async throws {
        for (total, output, words, minimum, maximum) in [(16_000, 2_000, 20_000, 4, 4),
            (16_000, 2_000, 30_000, 5, 5), (20_000, 8_000, 20_000, 4, 5)] {
            let environment = ReportFlowTestEnvironment(), access = BatchAIService()
            environment.aiAccess = access
            try await installSyntheticAI(environment, totalBudget: total, outputLimit: output)
            let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("scale-31", user: String(repeating: " evidence", count: words))])
            flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
            flow.send(.generateReport); await flow.waitForGeneration()
            let scale = try #require(flow.generationScale)
            #expect(scale.minimumRequests == minimum && scale.maximumRequests == maximum)
            #expect((flow.confirmation != nil) == (maximum > 4))
            if maximum > 4 {
                #expect(await access.requests.isEmpty)
                flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
            }
            #expect(flow.hasDraft && flow.generationError == nil)
            #expect(await access.requests.count <= maximum)
        }
    }

    @Test func aChangedPendingInputIsReplannedAndRequiresANewConfirmation() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("confirm-31", user: String(repeating: " evidence", count: 40_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        let old = try #require(flow.confirmation)
        flow.send(.requestSettingsPage(.general))
        var edit = flow.generalSettingsEdit; edit.outputLanguage = .english; edit.generationPreferences = "NEW_PREFERENCE_31"
        flow.send(.editGeneralSettings(edit, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.confirm(old.id)); await flow.waitForGeneration()
        let refreshed = try #require(flow.confirmation)
        #expect(refreshed.id != old.id && refreshed.generationContext?.settings.outputLanguage == .english)
        #expect(await access.requests.isEmpty)
        flow.send(.confirm(old.id)); #expect(await access.requests.isEmpty)
        flow.send(.confirm(refreshed.id)); await flow.waitForGeneration()
        #expect(flow.body.hasPrefix("## Today’s Overview") && flow.generationError == nil)
        #expect(await access.requests.allSatisfy { $0.instruction.contains("NEW_PREFERENCE_31") })
    }

    @Test(arguments: [true, false])
    func aNecessaryFailureOrCancellationStopsDispatchAndPreservesTheOldBody(_ failure: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(holds: true)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("stop-31", user: String(repeating: " evidence", count: 60_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.editBody("保留原正文", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        flow.send(.generateReport); flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await access.waitForRequests(3)
        if failure { await access.release(0, failure: .network) }
        else { flow.send(.cancelGeneration); #expect(flow.activeGenerationDay == nil) }
        await flow.waitForGeneration()
        #expect(flow.generationError == (failure ? .network : .cancelled))
        #expect(flow.body == "保留原正文" && flow.generationSources == nil)
        #expect(await access.requests.count == 3)
        #expect(await access.cancelled == (failure ? 2 : 3))
    }

    @Test func mergeCannotReplaceRelevantUpstreamFactsWithAnEmptyResult() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .eraseOnMerge)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("erase-31",
            user: String(repeating: "完整当天事实，保留所有风险。", count: 4_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.generationError == .invalidResponse && !flow.hasDraft)
    }
    @Test(arguments: [1, 3, 8])
    func boundedConcurrencyWaitsForUpstreamAndOutOfOrderResponsesKeepOriginalOrder(_ concurrency: Int) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(holds: true)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        var settings = try await environment.storage.load().aiServices
        settings.configurations[.chatCompletions]!.configuration.concurrency = concurrency
        await environment.storage.setAISettings(settings)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("concurrent-31",
            user: String(repeating: "完整当天👩🏽‍💻，结果未知。\n", count: 4_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        let scale = try #require(flow.confirmation?.generationScale)
        #expect(scale.extractionRequests >= concurrency)
        flow.send(.confirm(try #require(flow.confirmation).id))
        await access.waitForRequests(concurrency)
        #expect(flow.generationInFlightRequests == concurrency)
        #expect(await access.requests.count == concurrency)
        await access.release(concurrency - 1)
        await access.waitForRequests(concurrency + 1)
        #expect(flow.generationCompletedRequests == 1 && flow.generationInFlightRequests == concurrency)
        let initial = await access.requests
        #expect(initial.allSatisfy { if case .extractFacts = $0.intent { true } else { false } })
        await access.releaseAll(); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationError == nil)
        let final = try #require(await access.requests.last)
        let blocks = try final.additionalInputs.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        #expect(blocks.compactMap { $0["id"] as? Int } == Array(1...scale.extractionRequests))
        #expect(environment.generationEvents.allSatisfy { $0.inFlightRequests <= concurrency })
    }

    @Test(arguments: [BatchAIService.Mode.missingCoverage, .duplicateCoverage, .invalidReference, .wrongTurn,
                      .partialCompletion, .numericTurn, .oversized, .malformed, .duplicateFields,
                      .emptyReference, .duplicateReference, .emptyTurns, .duplicateTurns, .emptySummary, .wrongRelevance])
    func invalidIntermediateResultsNeverBecomePartialDrafts(_ mode: BatchAIService.Mode) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: mode)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("invalid-31",
            user: String(repeating: "当天完整内容，结果待确认👩🏽‍💻。", count: 2_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("原手写正文必须保留", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.generateReport); flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.generationError == (mode == .oversized ? .budget : .invalidResponse))
        #expect(flow.body == "原手写正文必须保留" && flow.generationSources == nil)
        #expect(flow.savedAIService.hasMatchingValidation)
        #expect(await access.requests.allSatisfy { if case .composeReport = $0.intent { false } else { true } })
    }

    @Test func denseSummariesUseFiniteMergeLayersAndStopAsSoonAsTheyFit() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .dense)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("dense-31",
            user: String(repeating: "完整当天事实，保留所有结果与风险。", count: 4_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        let scale = try #require(flow.confirmation?.generationScale)
        #expect(scale.mergeLayers >= 2)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationError == nil)
        let requests = await access.requests
        #expect(requests.contains { if case .mergeFacts = $0.intent { true } else { false } })
        #expect(requests.count < scale.maximumRequests)
        let tokenizer = OfflineReportTokenizer()
        for request in requests {
            var tokens = try await tokenizer.count(request.instruction) + tokenizer.count(request.input) + 1_024
            if let schema = request.schema {
                tokens += try await tokenizer.count(AIServiceClient.serializedFormat(schema, configuration: request.configuration))
            }
            for block in request.additionalInputs { tokens += try await tokenizer.count(block) }
            #expect(tokens <= 7_200)
            #expect(request.configuration.outputLimit == 3_000)
        }
    }
    @Test func confirmedPlanProcessesEveryCharacterAndCreatesOneAtomicDraft() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let text = String(repeating: "完整保留👩🏽‍💻e\u{301}、先失败再修复。\n", count: 2_000)
        let candidate = CodexCandidateSession(id: "unicode-31", title: "合成 unicode-31", workDirectory: nil, origin: .user,
            turns: [.init(id: "private-turn", startedAt: environment.now, day: ReportDay(date: environment.now, timeZone: .gmt),
                userText: text, finalAnswer: "已完成合成任务")], background: [])
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.body.contains("## 完成事项"))
        #expect(flow.generationError == nil)
        let requests = await access.requests
        var fragments: [[String: Any]] = []
        for request in requests {
            if case .extractFacts = request.intent {
                let value = try #require(try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any])
                fragments += try #require(value["fragments"] as? [[String: Any]])
            }
        }
        let ordered = fragments.sorted { ($0["id"] as! Int) < ($1["id"] as! Int) }
        #expect(ordered.enumerated().allSatisfy { offset, value in
            value["id"] as? Int == offset + 1 && value["part"] as? Int == offset + 1 && value["parts"] as? Int == ordered.count
                && value["session"] as? Int == 1 && value["order"] as? Int == 1
                && value["date"] as? String == flow.selectedDay.calendarDate && value["timeZone"] as? String == flow.selectedDay.timeZoneIdentifier
                && (value["result"] as? String)?.contains("final_answer_available") == true
        })
        let preservesEveryByte = ordered.compactMap { $0["user"] as? String }.joined().utf8.elementsEqual(text.utf8)
        #expect(preservesEveryByte)
        #expect(ordered.compactMap { $0["finalAnswer"] as? String }.joined() == "已完成合成任务")
        #expect(flow.generationSources?.groups.first?.titles == ["合成 unicode-31"])
        #expect(await environment.codex.scanCount == 1)
        #expect(environment.generationEvents.last?.path == .batched)
        #expect(environment.generationEvents.last?.completedRequests == requests.count)
    }
    @Test func longInputIsPlannedBeforeSendingAndNeverDiscarded() async throws {
        let environment = ReportFlowTestEnvironment()
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let text = String(repeating: "完整保留👩🏽‍💻e\u{301}、状态尚未确认。\n", count: 2_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("long-31", user: text)])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.generationError == nil)
        #expect(flow.confirmation != nil)
        #expect(await environment.ai.requests.isEmpty)
        #expect(flow.confirmedSnapshot?.sessions.first?.turns.first?.userText == text)
    }
}
