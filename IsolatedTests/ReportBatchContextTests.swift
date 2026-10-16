import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportBatchContextTests {
    @Test(arguments: [false, true])
    func aFinishedPlanRefreshesTheOpenCloseOrQuitConfirmationInsteadOfReplacingIt(_ quitting: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("close-plan-31", user: String(repeating: " evidence", count: 40_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        // Both actions run synchronously before the newly scheduled planner can return.
        flow.send(.generateReport); flow.send(quitting ? .quit : .requestCloseReport(session))
        let before = try #require(flow.confirmation)
        await flow.waitForGeneration()
        let after = try #require(flow.confirmation)
        switch after.kind {
        case .close(let target): #expect(!quitting && target == session)
        case .quit: #expect(quitting)
        default: Issue.record("计划回调覆盖了已有关闭／退出确认"); return
        }
        #expect(after.id != before.id && after.isGenerating)
        #expect(await access.requests.isEmpty)
        flow.send(.confirm(before.id))
        #expect(flow.openWindows[.report] == session && flow.activeGenerationDay != nil)
        flow.send(.cancelConfirmation)
        #expect(flow.activeGenerationDay != nil)
        flow.send(.generateReport)
        let plan = try #require(flow.confirmation)
        #expect(plan.generationScale?.requiresConfirmation == true)
        flow.send(.confirm(plan.id)); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationError == nil && flow.openWindows[.report] == session)
    }

    @Test func auxiliaryMaterialsStayInTheirStageAndSkipOversizedWholeUnits() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .dense)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        var settings = DailyReportGeneralSettings(); settings.historyLookbackDays = 2
        await environment.storage.setGeneralSettings(settings)
        let today = ReportDay(date: environment.now, timeZone: .gmt)
        func prior(_ offset: Int) -> ReportDay {
            ReportDay(date: today.calendar.date(byAdding: .day, value: -offset, to: today.start)!, timeZone: .gmt)
        }
        try await environment.storage.save(.init(day: prior(1), markdown: String(repeating: "NEAR_HISTORY_TOO_LARGE_31 ", count: 3_000), savedAt: environment.now, lastEditedAt: nil))
        try await environment.storage.save(.init(day: prior(2), markdown: "OLDER_HISTORY_USED_31", savedAt: environment.now, lastEditedAt: nil))
        let sessions = (1...2).map { number in
            CodexCandidateSession(id: "private-session-\(number)", title: "合成会话 \(number)", workDirectory: nil, origin: .user,
                turns: [.init(id: "today", startedAt: environment.now, day: today,
                    userText: String(repeating: " evidence", count: 20_000), finalAnswer: nil)],
                background: [
                    .init(id: "large", startedAt: environment.now.addingTimeInterval(-1), day: prior(1),
                        userText: String(repeating: "BACKGROUND_TOO_LARGE_31 ", count: 3_000), finalAnswer: nil),
                    .init(id: "small", startedAt: environment.now.addingTimeInterval(-2), day: prior(1),
                        userText: "BACKGROUND_USED_\(number)_31", finalAnswer: nil)
                ])
        }
        let flow = try await prepareSessionFlow(environment, sessions: sessions)
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        #expect(flow.hasDraft && flow.generationError == nil)
        let requests = await access.requests
        var usedBackground = Set<String>()
        let tokenizer = OfflineReportTokenizer()
        for request in requests {
            var object = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
            let background = object["background"] as! [[String: Any]], history = object["historicalReports"] as! [[String: Any]]
            switch request.intent {
            case .extractFacts:
                let sessions = Set((object["fragments"] as! [[String: Any]]).map { $0["session"] as! Int })
                #expect(background.allSatisfy { sessions.contains($0["session"] as! Int) })
                #expect(history.isEmpty)
                usedBackground.formUnion(background.map { $0["user"] as! String })
                object["fragments"] = []
            case .mergeFacts:
                #expect(background.isEmpty && history.isEmpty)
            case .composeReport:
                #expect(background.isEmpty && history.map { $0["markdown"] as! String } == ["OLDER_HISTORY_USED_31"])
            case .probe: Issue.record("生成不能探测协议")
            }
            object["background"] = []; object["historicalReports"] = []
            let marker = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            let auxiliary = String(decoding: try JSONSerialization.data(withJSONObject: ["background": background, "historicalReports": history], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            let schema = try #require(request.schema)
            let fixed = try await tokenizer.count(request.instruction) + tokenizer.count(AIServiceClient.serializedFormat(schema, configuration: request.configuration)) + 1_024
            let bodySpace = try await 7_200 - fixed - tokenizer.count(marker)
            #expect(try await tokenizer.count(auxiliary) <= bodySpace / 5)
            #expect(!request.input.contains("TOO_LARGE_31"))
        }
        #expect(usedBackground == ["BACKGROUND_USED_1_31", "BACKGROUND_USED_2_31"])
        #expect(flow.generationSources?.historyDays == [prior(2)])
        #expect(environment.generationEvents.last?.result == .degraded)
        #expect(!flow.body.contains("BACKGROUND_") && !flow.body.contains("HISTORY_"))
    }

    @Test func allLaterRequestsKeepTheStartingConfigurationAndSavedHistory() async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .dense, holds: true)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let today = ReportDay(date: environment.now, timeZone: .gmt)
        let yesterday = ReportDay(date: today.calendar.date(byAdding: .day, value: -1, to: today.start)!, timeZone: .gmt)
        try await environment.storage.save(.init(day: yesterday, markdown: "FROZEN_HISTORY_31", savedAt: environment.now, lastEditedAt: nil))
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("frozen-31", user: String(repeating: " evidence", count: 40_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await access.waitForRequests(3)
        let starting = try #require(await access.requests.first)
        flow.send(.requestSettingsPage(.aiServices))
        var serviceEdit = flow.aiServiceEdit
        serviceEdit.totalBudget = "14000"; serviceEdit.outputLimit = "3500"; serviceEdit.concurrency = "1"
        flow.send(.editAIService(serviceEdit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        var edit = flow.generalSettingsEdit
        edit.outputLanguage = .english; edit.generationPreferences = "NEXT_RUN_PREFERENCE_31"; edit.historyLookbackDays = 0
        flow.send(.editGeneralSettings(edit, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings); await flow.waitForStorage()
        flow.send(.selectReportDay(yesterday))
        flow.send(.editBody("NEW_HISTORY_31", day: yesterday, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        flow.send(.save); flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        flow.send(.selectReportDay(today))
        #expect(flow.activeGenerationDay == today && flow.savedAIService.validation.status == .needsRevalidation)
        await access.release(0); await access.waitForRequests(4)
        #expect(flow.generationInFlightRequests == 3)
        await access.releaseAll(); await flow.waitForGeneration()
        let requests = await access.requests
        #expect(requests.allSatisfy { $0.configuration == starting.configuration && $0.credential == starting.credential })
        #expect(requests.allSatisfy { !$0.instruction.contains("NEXT_RUN_PREFERENCE_31") && !$0.input.contains("NEW_HISTORY_31") })
        #expect(requests.last?.input.contains("FROZEN_HISTORY_31") == true)
        #expect(flow.body.hasPrefix("## 今日概览") && flow.generationSources?.historyDays == [yesterday])
        #expect(!flow.canGenerateReport)
    }

    @Test func redactionFailureIsVisibleWhileThePlanIsWaitingAndBeforeAnyRequest() async throws {
        enum Failure: Error { case synthetic }
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        environment.redact = { if $0.contains("FAIL_REDACTION_31") { throw Failure.synthetic }; return $0 }
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        var settings = DailyReportGeneralSettings(); settings.generationPreferences = "FAIL_REDACTION_31"
        await environment.storage.setGeneralSettings(settings)
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("redaction-31", user: String(repeating: " evidence", count: 40_000))])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        #expect(flow.confirmation != nil && flow.generationRedactionFailed)
        #expect(await access.requests.isEmpty)
        flow.send(.cancelConfirmation)
        #expect(flow.activeGenerationDay == nil && flow.generationError == .cancelled)
    }
}
