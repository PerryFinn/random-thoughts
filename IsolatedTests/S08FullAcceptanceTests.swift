import Foundation
import Synchronization
import Testing
@testable import random_thoughts

@MainActor
struct S08FullAcceptanceTests {
    @Test func node14ComponentKeepsTheFullProductionRequest() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let full = S08FullService(plan: plan, failure: .none)
        _ = await S08FullAcceptance.run(plan: plan, credential: "SYNTHETIC_FIDELITY_KEY", access: full, review: { _, _ in ["state"] })
        let step = try #require(plan.extraction.first { $0.id == 14 })
        let wholeRequest = try #require(await full.requests().first { $0.input == step.input })
        let component = S08CompactAIService(plan: plan)
        _ = try await ReportBatchExecutor(plan: plan, credential: "SYNTHETIC_FIDELITY_KEY", access: component,
            redact: { $0 }, progress: { _ in }).execute(step, upstream: [:])
        let request = try #require(await component.exchanges.first?.request)
        #expect(request.input.utf8.elementsEqual(wholeRequest.input.utf8))
        #expect(request.instruction == wholeRequest.instruction && request.schema == wholeRequest.schema)
        #expect(request.configuration == wholeRequest.configuration && request.credential == wholeRequest.credential)
        #expect(request.streaming == wholeRequest.streaming && request.additionalInputs == wholeRequest.additionalInputs)
    }

    @Test func twoFullRunsUseTheProductionLayersAndIndependentNodeEvidence() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .none)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in [] })
        #expect(batch.passed)
        #expect(batch.maximumHTTP == 65 && batch.rounds.count == 2)
        #expect(batch.rounds.allSatisfy { $0.status == .passed && $0.composed && $0.actualMergeLayers >= 2 })
    }

    @Test func aConfirmedDraftOutputIsNotAnOverallRuleCompletionClaim() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .confirmedDraft)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in [] })
        #expect(batch.passed)
    }

    @Test func aProductionRejectionStopsTheFirstFullRunAndPreservesItsPredicate() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .association)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY", access: access, review: { _, _ in [] })
        #expect(!batch.passed && batch.rounds.map(\.status) == [.failed, .unstarted])
        let failed = try #require(batch.rounds[0].nodes.first { $0.id == 6 })
        #expect(failed.accepted == false)
        #expect(failed.observation.rejections == [.init(node: 6, predicate: .turnAssociation, fact: 1)])
        #expect(!batch.rounds[0].composed && batch.rounds[1].nodes.allSatisfy { !$0.dispatched })
        let serialized = String(decoding: try JSONEncoder().encode(batch), as: UTF8.self)
        #expect(!serialized.contains("SYNTHETIC_PRIVATE") && !serialized.contains("summary"))
    }

    @Test(arguments: [S08FullService.Failure.empty, .transport, .early])
    fileprivate func retentionTransportAndEarlyCompositionStopWithoutStartingTheSecondRun(_ failure: S08FullService.Failure) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: failure)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in [] })
        #expect(!batch.passed && batch.rounds[1].status == .unstarted)
        let round = batch.rounds[0]
        switch failure {
        case .transport: #expect(round.status == .incomplete && round.error == "network")
        case .empty:
            let node = try #require(round.nodes.first { $0.id == 6 })
            #expect(node.accepted == true && node.retained == false)
            #expect(round.issues.contains("turnRetention") && !round.composed)
        default: #expect(round.composed && round.actualMergeLayers == 0 && round.issues.contains("multiLayerCoverage"))
        }
    }

    @Test func aSecondRunSemanticFailureCannotBeCoveredByTheFirstPassingRun() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .none)
        let calls = Mutex(0)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in
            calls.withLock { count in count += 1; return count == 1 ? [] : ["crossedCause"] }
        })
        #expect(!batch.passed && batch.rounds.map(\.status) == [.passed, .failed])
        #expect(batch.rounds[1].issues == ["crossedCause"])
    }

    @Test func semanticFailureDoesNotHideAnIndependentMissingMergeLayer() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .early)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in ["state"] })
        #expect(batch.rounds[0].issues.contains("state"))
        #expect(batch.rounds[0].issues.contains("multiLayerCoverage"))
        #expect(batch.rounds.map(\.status) == [.failed, .unstarted])
    }

    @Test func invalidCompositionFailsBeforeInvokingTheSemanticReviewer() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .badComposition)
        let calls = Mutex(0)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { _, _ in
            calls.withLock { $0 += 1 }
            return []
        })
        #expect(calls.withLock { $0 } == 0)
        #expect(batch.rounds.map(\.status) == [.failed, .unstarted])
        #expect(batch.rounds[0].issues.contains("compositionPayload"))
    }

    @Test func inMemoryReviewReceivesAllValidatedNodesAndPersistsOnlyItsVerdict() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = S08FullService(plan: plan, failure: .none)
        let calls = Mutex(0)
        let batch = await S08FullAcceptance.run(plan: plan, credential: "", access: access, review: { payload, nodes in
            calls.withLock { $0 += 1 }
            #expect(nodes.count == 30 && nodes.allSatisfy { !$0.block.isEmpty })
            #expect((try? ReportPayload.render(payload, language: .english)) != nil)
            return ["state"]
        })
        #expect(calls.withLock { $0 } == 1)
        #expect(batch.rounds.map(\.status) == [.failed, .unstarted] && batch.rounds[0].issues == ["state"])
        let record = String(decoding: try JSONEncoder().encode(batch), as: UTF8.self)
        #expect(!record.contains("summary") && !record.contains("factual") && !record.contains("report"))
    }
}

private actor S08FullService: AIServiceAccess {
    enum Failure: Sendable { case association, none, empty, transport, early, confirmedDraft, badComposition }
    let upstream: S08CompactAIService
    let input: String
    let failure: Failure
    init(plan: ReportBatchPlan, failure: Failure) {
        upstream = S08CompactAIService(plan: plan)
        input = plan.extraction.first { $0.id == 6 }!.input
        self.failure = failure
    }
    func requests() async -> [AIRequest] { await upstream.exchanges.map(\.request) }
    func execute(_ request: AIRequest) async throws -> String {
        if failure == .badComposition, case .composeReport = request.intent { return "{}" }
        if failure == .early, case .extractFacts = request.intent {
            let source = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
            let fragments = source["fragments"] as! [[String: Any]]
            let groups = fragments.map { fragment in
                ["references": [fragment["id"]!], "status": "unconfirmed",
                 "facts": [["turns": [fragment["association"]!], "summary": "Synthetic draft."]]] as [String: Any]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["covered": fragments.map { $0["id"]! }, "noRelevantContent": false, "groups": groups]), as: UTF8.self)
        }
        if request.input == input, failure == .transport { throw AIRequestError.network }
        if request.input == input, failure == .empty {
            return #"{"covered":[22,23,24,25],"noRelevantContent":true,"groups":[]}"#
        }
        if request.input == input, failure == .association {
            return #"{"covered":[22,23,24,25],"noRelevantContent":false,"groups":[{"references":[22],"status":"unconfirmed","facts":[{"turns":["7/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"},{"turns":["7/2"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
        }
        let result = try await upstream.execute(request)
        return request.input == input && failure == .confirmedDraft
            ? result.replacingOccurrences(of: "\"unconfirmed\"", with: "\"confirmed\"") : result
    }
}
