import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportCompactFactFlowTests {
    @Test func s08FactsSurviveThreeProductionMergeLayersWithinTheOriginalBudgets() async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
        let plan = try await makePlan(scenario)
        let tokenizer = OfflineReportTokenizer()
        #expect(plan.visibleLimit == 1_500 && plan.factBudget.limit == 5_240 && plan.finalBudget.limit == 5_240)
        let schema = try #require(plan.factSchema)
        let properties = try #require(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])["properties"] as! [String: Any]
        #expect(Set(properties.keys) == ["covered", "noRelevantContent", "groups"])
        let nodeNote = "Input nodes replace facts with ordered groups [{status,facts:[{turns,summary}]}]. Flatten groups in order; each fact inherits its group's status. Other node fields are unchanged."
        #expect(plan.factInstruction.contains(nodeNote))
        #expect(plan.prepared.batchFinalInstruction.contains(nodeNote))
        #expect(plan.factInstruction.contains("Group only contiguous facts with identical references/status; no empty groups"))
        let marker = try plan.input(upstream: [Int.max, Int.max])
        let worstMerge = try await plan.factBudget.count(marker) + 2 * plan.visibleLimit
        let worstFinal = try await plan.finalBudget.count(marker) + 2 * plan.visibleLimit
        #expect(worstMerge <= 5_240 && worstFinal == 5_212)
        #expect(plan.finalBudget.limit - worstFinal == 28)
        print("S08 OFFLINE worst merge=\(worstMerge), composition=\(worstFinal)/\(plan.finalBudget.limit), visible=\(plan.visibleLimit)")

        let access = S08CompactAIService(plan: plan)
        let result = try await ReportBatchExecutor(plan: plan, credential: "", access: access, redact: { $0 }, progress: { _ in }).execute()
        #expect(result.payload == syntheticReportPayload)
        let exchanges = await access.exchanges
        let composition = try #require(exchanges.last)
        if case .composeReport = composition.request.intent {} else { Issue.record("Expected one final composition") }
        let steps = Dictionary(uniqueKeysWithValues: (plan.extraction + plan.mergeLayers.flatMap { $0 }).map { ($0.input, $0) })
        var blocks: [Int: String] = [:]
        for exchange in exchanges {
            let budget: ReportRequestBudget
            if case .composeReport = exchange.request.intent { budget = plan.finalBudget } else { budget = plan.factBudget }
            #expect(try await budget.count(exchange.request.input, blocks: exchange.request.additionalInputs) <= 5_240)
            #expect(exchange.request.configuration.totalBudget == 9_550 && exchange.request.configuration.outputLimit == 3_000)
            for block in exchange.request.additionalInputs {
                let node = try JSONDecoder().decode(S08CompactNode.self, from: Data(block.utf8))
                blocks[node.id] = block
            }
        }
        let layers = [Array(1...8), Array(17...20), [25, 26], [29]]
        var layerTokens: [Int] = []
        for ids in layers {
            var tokens = 0
            for id in ids {
                let block = try #require(blocks[id])
                let node = try JSONDecoder().decode(S08CompactNode.self, from: Data(block.utf8))
                let exchange = try #require(exchanges.first { steps[$0.request.input]?.id == id })
                let step = try #require(steps[exchange.request.input])
                let payload = try ReportFactPayload.parse(exchange.response)
                #expect(try await tokenizer.count(exchange.response) <= 1_500)
                let count = try await tokenizer.count(block)
                #expect(count <= 1_500)
                tokens += count
                let projected = payload.facts.map { ReportFactPayload.Fact(references: [id], turns: $0.turns, status: $0.status, summary: $0.summary) }
                #expect(try ReportJSON.encode(node.facts).utf8.elementsEqual(ReportJSON.encode(projected).utf8))
                #expect(node.completeTurns == Array(Set(payload.facts.flatMap(\.turns))).sorted())
                #expect(!node.noRelevantContent)
                if !step.upstream.isEmpty {
                    let parents = try step.upstream.map { try JSONDecoder().decode(S08CompactNode.self, from: Data(#require(blocks[$0]).utf8)) }
                    let inherited = parents.flatMap(\.facts)
                    #expect(try ReportJSON.encode(payload.facts).utf8.elementsEqual(ReportJSON.encode(inherited).utf8))
                    var parentTokens = 0
                    for parent in step.upstream { parentTokens += try await tokenizer.count(#require(blocks[parent])) }
                    #expect(count < parentTokens)
                }
            }
            layerTokens.append(tokens)
        }
        #expect(layerTokens == [1_592, 1_480, 1_424, 1_396])
        let root = try JSONDecoder().decode(S08CompactNode.self, from: Data(#require(blocks[29]).utf8))
        #expect(root.facts.count == 34 && root.completeTurns.count == 33)
        let rootExchange = try #require(exchanges.first { steps[$0.request.input]?.id == 29 })
        #expect(try await tokenizer.count(rootExchange.response) == 1_283)
        #expect(try #require(steps[rootExchange.request.input]).upstream == [25, 26])
        var originals: [ReportFactPayload.Fact] = []
        for (session, value) in scenario.sessions.prefix(9).enumerated() {
            for (order, turn) in value.turns.enumerated() {
                let answer = try #require(turn.finalAnswer)
                let blocker = " The shared synthetic schema mismatch blocks integrating these rules."
                originals.append(.init(references: [29], turns: ["\(session + 1)/\(order + 1)"],
                    status: session == 0 ? .confirmed : .unconfirmed, summary: answer.replacingOccurrences(of: blocker, with: "")))
                if answer.contains(blocker) {
                    originals.append(.init(references: [29], turns: ["\(session + 1)/\(order + 1)"], status: .unconfirmed,
                        summary: "The shared synthetic schema mismatch blocks integrating these rules; affected scope unspecified."))
                }
            }
        }
        #expect(try ReportJSON.encode(root.facts).utf8.elementsEqual(ReportJSON.encode(originals).utf8))
    }

    @Test func aWithinBudgetGroupedResponseStillFailsWhenRedactionMakesItsNodeTooLarge() async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
        let plan = try await makePlan(scenario), access = S08CompactAIService(plan: plan)
        await #expect(throws: AIRequestError.budget) {
            try await ReportBatchExecutor(plan: plan, credential: "", access: access,
                redact: { _ in String(repeating: " oversized", count: 1_600) }, progress: { _ in }).execute()
        }
        let exchanges = await access.exchanges
        #expect(!exchanges.isEmpty)
        for exchange in exchanges {
            #expect(try await plan.factBudget.tokenizer.count(exchange.response) <= plan.visibleLimit)
            if case .extractFacts = exchange.request.intent {} else { Issue.record("Oversized nodes must stop before merging or composition") }
        }
    }

    private func makePlan(_ scenario: ReportAcceptanceScenario) async throws -> ReportBatchPlan {
        var configuration = AIServiceConfiguration(service: .responses)
        configuration.endpoint = "https://s08-offline.invalid"; configuration.model = "offline-synthetic"
        configuration.totalBudget = 9_550; configuration.outputLimit = 3_000
        var service = SavedAIService(configuration: configuration)
        service.validation.structured = .supported
        let context = ReportGenerationContext(service: service,
            snapshot: .init(day: scenario.day, sessions: scenario.sessions, redactionFailed: false),
            settings: scenario.settings, history: scenario.history)
        guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: "", tokenizer: OfflineReportTokenizer(), redact: { $0 }) else {
            throw AIRequestError.budget
        }
        return plan
    }
}
