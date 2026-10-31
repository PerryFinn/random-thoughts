import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportFactContractTests {
    @Test func nodeEvidenceDropsValidatedOldReferencesButPreservesFactsAndWholeTurns() throws {
        let fact = ReportFactPayload.Fact(references: [23], turns: ["4/2"], status: .unconfirmed, summary: "A draft remains pending.")
        let block = try ReportJSON.encode(ReportFactNode.Input(id: 7, facts: [fact], noRelevantContent: false, completeTurns: ["4/2"]))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any])
        let evidence = try #require((object["facts"] as? [[String: Any]])?.first)
        #expect(Set(evidence.keys) == ["turns", "status", "summary"])
        #expect(object["id"] as? Int == 7 && object["completeTurns"] as? [String] == ["4/2"])
        #expect(evidence["turns"] as? [String] == fact.turns)
        #expect(evidence["status"] as? String == fact.status.rawValue && evidence["summary"] as? String == fact.summary)
        #expect(!block.contains("23"))
    }

    @Test(arguments: AIServiceType.allCases)
    func partialTurnSchemaFitsTheFullSchemaReservation(_ service: AIServiceType) async throws {
        let tokenizer = OfflineReportTokenizer(), configuration = AIServiceConfiguration(service: service)
        let full = try AIServiceClient.serializedFormat(ReportFactPayload.schema, configuration: configuration)
        let partial = try AIServiceClient.serializedFormat(ReportFactPayload.partialTurnSchema, configuration: configuration)
        #expect(try await tokenizer.count(partial) <= tokenizer.count(full))
    }

    @Test func wholeTurnsKeepConfirmedAvailableWhilePartialMergesCannotChooseIt() async throws {
        for split in [false, true] {
            let environment = ReportFlowTestEnvironment()
            let access = BatchAIService(mode: split ? .denseSchemaCompletion : .schemaCompletion)
            environment.aiAccess = access
            try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
            let sessions = split
                ? [syntheticCandidate("split-36", user: String(repeating: " evidence", count: 60_000))]
                : (1...2).map { syntheticCandidate("whole-36-\($0)", user: String(repeating: " evidence", count: 4_000)) }
            let flow = try await prepareSessionFlow(environment, sessions: sessions)
            flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
            flow.send(.generateReport); await flow.waitForGeneration()
            if let confirmation = flow.confirmation { flow.send(.confirm(confirmation.id)); await flow.waitForGeneration() }
            #expect(flow.generationError == nil && flow.hasDraft)
            let requests = await access.requests
            let facts = requests.filter { if case .composeReport = $0.intent { false } else { true } }
            #expect(!facts.isEmpty)
            #expect(facts.allSatisfy { $0.instruction.contains("Keep outputs with different completion states in separate facts; pending work NEVER downgrades an explicitly completed output") })
            #expect(facts.allSatisfy { $0.instruction.contains("A blocker summary contains ONLY its causal statement and explicit affected-scope assertions, never progress or reporting labels") })
            #expect(facts.allSatisfy { $0.instruction.contains("For matching source/output languages copy these statements verbatim; otherwise translate faithfully without adding subjects or affected items") })
            #expect(facts.allSatisfy { $0.schema == (split ? ReportFactPayload.partialTurnSchema : ReportFactPayload.schema) })
            #expect(facts.allSatisfy { $0.instruction.contains("Keep each causal blocker in a SEPARATE fact from draft/progress/review results") })
            #expect(facts.allSatisfy { $0.instruction.contains("its source association does NOT define affected scope") })
            #expect(facts.allSatisfy { $0.instruction.contains("Emit all causal blockers before compressed progress, even if mentioned once") })
            #expect(facts.allSatisfy { $0.instruction.contains("including when the statement has no pronoun; NEVER add an item prefix or suffix") })
            if split {
                let merges = facts.filter { if case .mergeFacts = $0.intent { true } else { false } }
                #expect(!merges.isEmpty)
                #expect(merges.allSatisfy { $0.instruction.contains("For merge, each output reference is the enclosing node.id; NEVER use turn numbers or earlier-stage IDs") })
                #expect(merges.allSatisfy { $0.instruction.contains("node id 7 with turns [\"4/2\"] becomes references [7] and turns [\"4/2\"]") })
                for request in merges {
                    for block in request.additionalInputs {
                        let node = try #require(try JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any])
                        let evidence = try #require(node["facts"] as? [[String: Any]])
                        #expect(evidence.allSatisfy { Set($0.keys) == ["turns", "status", "summary"] })
                    }
                }
            }
        }
    }

    @Test(arguments: [BatchAIService.Mode.schemaCompletion, .schemaAssociation])
    func schemaCompliantExtractionCannotChooseTheObservedInvalidStatusOrTurn(_ mode: BatchAIService.Mode) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(mode: mode)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let text = String(repeating: " evidence", count: 7_000)
        let candidate = syntheticCandidate("contract-36", user: text)
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        flow.send(.generateReport); await flow.waitForGeneration()
        if let confirmation = flow.confirmation { flow.send(.confirm(confirmation.id)); await flow.waitForGeneration() }
        #expect(flow.generationError == nil && flow.hasDraft)
        let requests = await access.requests
        let composition = try #require(requests.last)
        #expect(composition.instruction.contains("Unfinished, failed or blocked work, tests not run and missing evidence are statuses, NOT explicit TODOs"))
        #expect(composition.instruction.contains("An already attempted request is NOT a renewed request to retry"))
        #expect(composition.instruction.contains("If no qualifying future action is explicit in the evidence, plans MUST be an empty string"))
        expectBlockerEvidenceRules(in: composition.instruction)
        let extraction = requests.filter { if case .extractFacts = $0.intent { true } else { false } }
        #expect(extraction.count == 2)
        for request in extraction {
            let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
            let fragments = input["fragments"] as! [[String: Any]]
            #expect(fragments.allSatisfy { $0["association"] as? String == "1/1" })
            #expect(fragments.allSatisfy { $0["parts"] as? Int == 2 })
        }
        let ordered = try extraction.flatMap { request -> [[String: Any]] in
            (try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any])["fragments"] as! [[String: Any]]
        }.sorted { ($0["id"] as! Int) < ($1["id"] as! Int) }
        #expect(ordered.compactMap { $0["user"] as? String }.joined() == text)
        #expect(flow.generationSources?.groups.first?.titles == [candidate.title])
        #expect(await environment.codex.scanCount == 1)
    }
}
