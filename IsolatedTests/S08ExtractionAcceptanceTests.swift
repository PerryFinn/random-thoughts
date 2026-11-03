import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct S08ExtractionAcceptanceTests {
    @Test func twoOriginalExtractionRoundsStopBeforeMergingOrComposing() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08CompactAIService(plan: plan)
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "", access: access)
        #expect(result.admitted)
        #expect(result.rounds.count == 2 && result.rounds.allSatisfy { $0.status == .passed })
        for round in result.rounds {
            #expect(round.nodes.count == 16 && round.nodes.allSatisfy { $0.accepted == true && $0.retained == true })
            #expect(round.nodes.reduce(0) { $0 + $1.userBytes } == 80_648)
            #expect(round.nodes.reduce(0) { $0 + $1.answerBytes } == 6_833)
            #expect(Set(round.nodes.flatMap(\.expectedTurns)).count == 65)
        }
        let exchanges = await access.exchanges
        #expect(exchanges.count == 32)
        let onlyExtraction = exchanges.allSatisfy { if case .extractFacts = $0.request.intent { true } else { false } }
        #expect(onlyExtraction)
        for step in plan.extraction {
            let matching = exchanges.filter { $0.request.input == step.input }
            #expect(matching.count == 2)
        }
    }

    @Test func aReducedPlanCannotQualifyAsTheOriginalSixteenNodeBaseline() async throws {
        let original = try await makeOfflineS08LayeredPlan()
        let plan = try S08ExtractionPair.makePlan(from: original)
        let access = S08CompactAIService(plan: plan)
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "", access: access)
        #expect(!result.admitted && result.rounds.first?.status == .incomplete)
        let count = await access.exchanges.count
        #expect(count == 0)
    }

    @Test func sharedReferencesAndMultipleFactsForOneTurnRemainLegal() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let response = #"{"covered":[22,23,24,25],"noRelevantContent":false,"groups":[{"references":[22,23,24,25],"status":"unconfirmed","facts":[{"turns":["7/1","7/2","7/3","7/4"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"},{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
        let access = S08AcceptanceService(plan: plan, result: .success(response))
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "", access: access)
        #expect(result.admitted)
        for round in result.rounds {
            let node = try #require(round.nodes.first { $0.node == 6 })
            #expect(node.observation.groups?.first?.references == [22, 23, 24, 25])
            #expect(node.observation.groups?.first?.turns.count == 2)
        }
    }

    @Test func aSecondRoundFailurePreservesTheFirstRoundWithoutCombiningCoverage() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let response = #"{"covered":[22,23,24,25],"noRelevantContent":true,"groups":[]}"#
        let access = S08AcceptanceService(plan: plan, result: .success(response), occurrence: 2)
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "", access: access)
        #expect(!result.admitted)
        #expect(result.rounds.map(\.status) == [.passed, .rejected])
        #expect(result.rounds[0].nodes.allSatisfy { $0.retained == true })
        let node = try #require(result.rounds[1].nodes.first { $0.node == 6 })
        #expect(node.accepted == true && node.retained == false && node.observation.rejections.isEmpty)
        let count = await access.requests.count
        #expect(count == 32)
    }

    @Test(arguments: [true, false])
    func productionAcceptedEmptyOrMissingTurnsFailDigitalRetentionAndStopTheBatch(_ empty: Bool) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let response = empty
            ? #"{"covered":[22,23,24,25],"noRelevantContent":true,"groups":[]}"#
            : #"{"covered":[22,23,24,25],"noRelevantContent":false,"groups":[{"references":[22],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
        let access = S08AcceptanceService(plan: plan, result: .success(response))
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "", access: access)
        #expect(!result.admitted)
        let count = await access.requests.count
        #expect(count == 16)
    }

    @Test(arguments: [false, true])
    func nodeEvidenceSeparatesActualProductionRejectionFromTransportFailure(_ transport: Bool) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let payload = #"{"covered":[22,23,24,25],"noRelevantContent":false,"groups":[{"references":[22],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"},{"turns":["7/2"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
        let access = S08AcceptanceService(plan: plan, result: transport ? .failure(.network) : .success(payload))
        let result = await S08ExtractionAcceptance.run(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY", access: access)
        #expect(!result.admitted)
        let round = try #require(result.rounds.first)
        #expect(round.status == (transport ? .incomplete : .rejected))
        let node = try #require(round.nodes.first { $0.node == 6 })
        #expect(node.dispatched && node.returned == !transport)
        let accepted: Bool? = transport ? nil : false
        #expect(node.accepted == accepted && node.retained == nil)
        #expect(node.observation.rejections == (transport ? [] : [.init(node: 6, predicate: .turnAssociation, fact: 1)]))
        #expect(result.rounds.count == 2 && result.rounds[1].status == .unstarted)
        #expect(result.rounds[1].nodes.allSatisfy { !$0.dispatched && $0.accepted == nil })
        let text = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!text.contains("SYNTHETIC_PRIVATE") && !text.contains("summary") && !text.contains("https://"))
    }

}

private actor S08AcceptanceService {
    let upstream: S08CompactAIService
    let input: String
    let result: Result<String, AIRequestError>
    let occurrence: Int?
    private var matches = 0
    private(set) var requests: [AIRequest] = []

    init(plan: ReportBatchPlan, result: Result<String, AIRequestError>, occurrence: Int? = nil) {
        upstream = S08CompactAIService(plan: plan)
        input = plan.extraction.first { $0.id == 6 }!.input
        self.result = result
        self.occurrence = occurrence
    }

    func execute(_ request: AIRequest) async throws -> String {
        requests.append(request)
        if request.input == input {
            matches += 1
            if occurrence == nil || occurrence == matches { return try result.get() }
        }
        return try await upstream.execute(request)
    }
}

extension S08AcceptanceService: AIServiceAccess {}
