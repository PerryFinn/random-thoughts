import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportAcceptanceScenarioTests {
    @Test func missingHistoryDaysStayMissingAndHistoricalFactsRemainAuxiliary() async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S03" })
        let environment = ReportFlowTestEnvironment()
        try await installSyntheticAI(environment)
        let saved = try #require(try await environment.storage.load().aiServices.configurations[.chatCompletions])
        let flow = try await scenario.prepare(environment: environment, service: saved)
        await environment.ai.enqueue(.success(syntheticReportPayload))
        flow.send(.generateReport); await flow.waitForGeneration()
        let request = try #require(await environment.ai.requests.first)
        #expect(request.input.contains("2026-10-18"))
        #expect(!request.input.contains("2026-10-17") && !request.input.contains("六项性能测试"))
        #expect(flow.generationSources?.historyDays.map(\.calendarDate) == ["2026-10-18"])
        #expect(flow.confirmedSnapshot?.sessions.first?.turns.first?.day.calendarDate == "2026-10-20")
    }

    @Test func theLongTurnIsSplitWithoutLosingAnyUserOrFinalAnswerBytes() async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S07" })
        let environment = ReportFlowTestEnvironment(), access = BatchAIService()
        environment.aiAccess = access
        try await installSyntheticAI(environment, outputLimit: 3_000)
        let saved = try #require(try await environment.storage.load().aiServices.configurations[.chatCompletions])
        let flow = try await scenario.prepare(environment: environment, service: saved)
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        var fragments: [[String: Any]] = []
        for request in await access.requests {
            guard case .extractFacts = request.intent else { continue }
            let value = try #require(try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any])
            fragments += try #require(value["fragments"] as? [[String: Any]])
        }
        let sorted = fragments.sorted { ($0["id"] as! Int) < ($1["id"] as! Int) }
        let original = try #require(scenario.turns.first)
        #expect(sorted.count >= 2 && scenario.turns.count == 1)
        #expect(sorted.compactMap { $0["user"] as? String }.joined().utf8.elementsEqual(original.userText.utf8))
        #expect(sorted.compactMap { $0["finalAnswer"] as? String }.joined().utf8.elementsEqual((original.finalAnswer ?? "").utf8))
        #expect(flow.hasDraft && flow.generationError == nil)
    }

    @Test func oversizedAuxiliaryUnitsDoNotDisplaceAnyTodayTurnOrLaterShortHistory() async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: .noRelevant)
        environment.aiAccess = access
        try await installSyntheticAI(environment, outputLimit: 3_000)
        let saved = try #require(try await environment.storage.load().aiServices.configurations[.chatCompletions])
        let flow = try await scenario.prepare(environment: environment, service: saved)
        flow.send(.generateReport); await flow.waitForGeneration()
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForGeneration()
        var userBytes = 0, answerBytes = 0, turns = 0, background = 0
        let requests = await access.requests
        for request in requests {
            guard case .extractFacts = request.intent else { continue }
            let input = try #require(try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any])
            let fragments = try #require(input["fragments"] as? [[String: Any]])
            turns += fragments.count
            userBytes += fragments.reduce(0) { $0 + (($1["user"] as? String)?.utf8.count ?? 0) }
            answerBytes += fragments.reduce(0) { $0 + (($1["finalAnswer"] as? String)?.utf8.count ?? 0) }
            background += (input["background"] as? [Any])?.count ?? 0
            #expect(!request.input.contains("large background"))
        }
        #expect(scenario.sessions.count == 17 && turns == 65 && background == 16)
        #expect(userBytes == scenario.userBytes && answerBytes == scenario.answerBytes)
        #expect(flow.generationSources?.historyDays.map(\.calendarDate) == ["2026-10-18"])
        #expect(environment.generationEvents.last?.result == .degraded)
        #expect(requests.last?.input.contains("large history") == false)
    }
}
