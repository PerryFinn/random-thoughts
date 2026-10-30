import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportFactContractTests {
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
            #expect(facts.allSatisfy { $0.schema == (split ? ReportFactPayload.partialTurnSchema : ReportFactPayload.schema) })
            #expect(facts.allSatisfy { $0.instruction.contains("Keep each causal blocker in a SEPARATE fact from draft/progress/review results") })
            #expect(facts.allSatisfy { $0.instruction.contains("its source association does NOT define affected scope") })
            #expect(facts.allSatisfy { $0.instruction.contains("Emit all causal blockers before compressed progress, even if mentioned once") })
            #expect(facts.allSatisfy { $0.instruction.contains("retain its pronouns and state that affected scope is unspecified") })
            if split { #expect(facts.contains { if case .mergeFacts = $0.intent { true } else { false } }) }
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
