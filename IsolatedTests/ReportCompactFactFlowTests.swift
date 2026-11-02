import Foundation
import Synchronization
import Testing
@testable import random_thoughts

@MainActor
struct ReportCompactFactFlowTests {
    @Test(arguments: [true, false])
    func sameStatusFactsFromDifferentFragmentsKeepTheirOwnReferences(_ wrongReference: Bool) async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
        let original = try await makePlan(scenario)
        let plan = try S08ExtractionPair.makePlan(from: original)
        let step = try #require(plan.extraction.first)
        #expect(plan.extraction.count == 1 && step.fragments.map(\.id) == [22, 23])
        var input = try #require(JSONSerialization.jsonObject(with: Data(step.input.utf8)) as? [String: Any])
        let source = try #require(original.extraction.first { $0.id == 6 })
        var full = try #require(JSONSerialization.jsonObject(with: Data(source.input.utf8)) as? [String: Any])
        input.removeValue(forKey: "fragments"); full.removeValue(forKey: "fragments")
        #expect(NSDictionary(dictionary: input).isEqual(to: full))
        let access = ControlledAIService()
        let payload = wrongReference
            ? #"{"covered":[22,23],"noRelevantContent":false,"groups":[{"references":[22],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"First draft pending."},{"turns":["7/2"],"summary":"Second draft pending."}]}]}"#
            : #"{"covered":[22,23],"noRelevantContent":false,"groups":[{"references":[22],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"First draft pending."}]},{"references":[23],"status":"unconfirmed","facts":[{"turns":["7/2"],"summary":"Second draft pending."}]}]}"#
        await access.enqueue(.success(payload))
        await access.enqueue(.success(syntheticReportPayload))
        let rejections = Mutex<[ReportBatchExecutor.Rejection]>([])
        let executor = ReportBatchExecutor(plan: plan, credential: "", access: access, redact: { $0 }, progress: { _ in },
            onRejection: { rejection in rejections.withLock { $0.append(rejection) } })
        if wrongReference {
            await #expect(throws: AIRequestError.invalidResponse) { try await executor.execute() }
        } else {
            let output = try await executor.execute()
            #expect(output.payload == syntheticReportPayload)
        }
        #expect(rejections.withLock { $0 } == (wrongReference
            ? [.init(node: 6, predicate: .turnAssociation, fact: 1)] : []))
    }

    @Test(arguments: [false, true])
    func extractionDiagnosticsKeepOriginalGroupsAndAcceptLegalSharedReferences(_ shared: Bool) async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
        let plan = try S08ExtractionPair.makePlan(from: await makePlan(scenario))
        let access = ControlledAIService(), diagnostics = S08ExtractionDiagnostics()
        // Adjacent identical groups must remain separate in the observation.
        let payload = shared
            ? #"{"covered":[22,23],"noRelevantContent":false,"groups":[{"references":[22,23],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"},{"turns":["7/2"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
            : #"{"covered":[22,23],"noRelevantContent":false,"groups":[{"references":[22,23],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]},{"references":[22,23],"status":"unconfirmed","facts":[{"turns":["7/2"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
        await access.enqueue(.success(payload))
        await access.enqueue(.success(syntheticReportPayload))
        let output = try await ReportBatchExecutor(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY",
            access: S08ExtractionDiagnosticAccess(upstream: access, diagnostics: diagnostics),
            redact: { $0 }, progress: { _ in }, onRejection: { diagnostics.reject($0) }).execute()
        #expect(output.payload == syntheticReportPayload)
        let observation = diagnostics.observation
        #expect(observation.covered == [22, 23] && observation.rejections.isEmpty)
        let expected: [S08ExtractionDiagnostics.Group] = shared
            ? [.init(references: [22, 23], status: 1, turns: [[[7, 1]], [[7, 2]]])]
            : [.init(references: [22, 23], status: 1, turns: [[[7, 1]]]),
               .init(references: [22, 23], status: 1, turns: [[[7, 2]]])]
        #expect(observation.groups == expected)
        let encoded = String(decoding: try JSONEncoder().encode(observation), as: UTF8.self)
        #expect(!encoded.contains("SYNTHETIC_PRIVATE") && !encoded.contains("summary"))
    }

    @Test(arguments: [ReportBatchExecutor.Rejection.Predicate.payloadParsing, .coveredCount, .coveredIDs,
        .relevanceFlag, .emptyReferences, .duplicateReferences, .referenceBounds, .emptyTurns,
        .duplicateTurns, .emptySummary, .turnAssociation, .rawVisibleBudget])
    func extractionDiagnosticsReportActualRejectionsWithoutChangingTheVerdict(_ predicate: ReportBatchExecutor.Rejection.Predicate) async throws {
        let scenario = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
        let plan = try S08ExtractionPair.makePlan(from: await makePlan(scenario))
        var evidence: [String: Any] = ["turns": ["7/1"], "summary": "SYNTHETIC_PRIVATE_SUMMARY"]
        var group: [String: Any] = ["references": [22], "status": "unconfirmed"]
        var root: [String: Any] = ["covered": [22, 23], "noRelevantContent": false]
        switch predicate {
        case .payloadParsing: root["SYNTHETIC_PRIVATE_FIELD"] = "SYNTHETIC_PRIVATE_VALUE"
        case .coveredCount: root["covered"] = [22]
        case .coveredIDs: root["covered"] = [22, 22]
        case .relevanceFlag: root["noRelevantContent"] = true
        case .emptyReferences: group["references"] = [Int]()
        case .duplicateReferences: group["references"] = [22, 22]
        case .referenceBounds: group["references"] = [99]
        case .emptyTurns: evidence["turns"] = [String]()
        case .duplicateTurns: evidence["turns"] = ["7/1", "7/1"]
        case .emptySummary: evidence["summary"] = "  \n"
        case .turnAssociation: evidence["turns"] = ["SYNTHETIC_PRIVATE_TURN"]
        case .rawVisibleBudget: evidence["summary"] = String(repeating: " oversized", count: 1_600)
        default: Issue.record("Unexpected fixture predicate"); return
        }
        group["facts"] = [evidence]; root["groups"] = [group]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        for enabled in [false, true] {
            let access = ControlledAIService(), diagnostics = S08ExtractionDiagnostics()
            await access.enqueue(.success(payload))
            let executor = ReportBatchExecutor(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY",
                access: S08ExtractionDiagnosticAccess(upstream: access, diagnostics: diagnostics),
                redact: { $0 }, progress: { _ in }, onRejection: { if enabled { diagnostics.reject($0) } })
            await #expect(throws: predicate == .rawVisibleBudget ? AIRequestError.budget : .invalidResponse) {
                try await executor.execute()
            }
            let factPredicates: Set<ReportBatchExecutor.Rejection.Predicate> = [.emptyReferences, .duplicateReferences,
                .referenceBounds, .emptyTurns, .duplicateTurns, .emptySummary, .turnAssociation]
            let expected = ReportBatchExecutor.Rejection(node: 6, predicate: predicate,
                fact: factPredicates.contains(predicate) ? 0 : nil)
            #expect(diagnostics.observation.rejections == (enabled ? [expected] : []))
            #expect(await access.requests.count == 1)
            if predicate == .turnAssociation {
                #expect(diagnostics.observation.groups?.first?.turns == [[[nil]]])
            }
            let encoded = String(decoding: try JSONEncoder().encode(diagnostics.observation), as: UTF8.self)
            #expect(!encoded.contains("SYNTHETIC_PRIVATE") && !encoded.contains("summary"))
        }
    }

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
