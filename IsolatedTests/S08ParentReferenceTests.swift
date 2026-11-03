import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct S08ParentReferenceTests {
    @Test(arguments: [false, true])
    func sixFixedMergeResultsReuseValidatedParentsAndKeepTargetFailures(_ omit: Bool) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = ParentReferenceFixtureService(plan: plan, mode: omit ? .omission : .shared)
        let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: "", access: access)
        #expect(result.ready && result.complete)
        #expect(result.preparation.count == 2 && result.preparation.allSatisfy { $0.accepted == true && $0.retained == true })
        #expect(result.preparation.map(\.references) == [[58, 59, 60, 61], [62, 63, 64, 65]])
        #expect(result.attempts.count == 6)
        let rejections: [ReportBatchExecutor.Rejection] = omit ? [.init(node: 24, predicate: .nonemptyParents, fact: nil)] : []
        #expect(result.attempts.allSatisfy { $0.result.accepted == !omit && $0.result.observation.rejections == rejections })
        let requests = await access.requests
        #expect(requests.count == 8)
        let merging = requests.filter { if case .mergeFacts = $0.intent { true } else { false } }
        #expect(merging.count == 6)
        let identicalParents = merging.allSatisfy { $0.additionalInputs == merging.first?.additionalInputs }
        #expect(identicalParents)
        let safeIntents = requests.allSatisfy {
            switch $0.intent { case .extractFacts, .mergeFacts: true; default: false }
        }
        #expect(safeIntents)
        let text = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!text.contains("SYNTHETIC_PRIVATE") && !text.contains("summary") && !text.contains("https://"))
    }

    @Test func theComponentRefusesCompositionAndProbesBeforeAccessingTheService() async throws {
        for intent in [AIRequestIntent.composeReport, .probe(.basic)] {
            let upstream = ControlledAIService()
            let observer = S08ParentFactAccess(upstream: upstream, diagnostics: S08ExtractionDiagnostics())
            let request = AIRequest(intent: intent, configuration: .init(service: .responses),
                credential: "SYNTHETIC_PRIVATE_KEY", instruction: "synthetic", input: "{}", schema: nil, streaming: false)
            await #expect(throws: AIRequestError.parameters) { try await observer.execute(request) }
            let count = await upstream.requests.count
            #expect(count == 0)
            #expect(!observer.state.withLock { $0.dispatched })
        }
    }

    @Test func reducedPlansCannotStartTheFrozenParentDiagnosticBatch() async throws {
        let original = try await makeOfflineS08LayeredPlan()
        let plan = ReportBatchPlan(prepared: original.prepared,
            extraction: original.extraction.filter { [15, 16].contains($0.id) }, mergeLayers: original.mergeLayers,
            visibleLimit: original.visibleLimit, factInstruction: original.factInstruction, factSchema: original.factSchema,
            factBudget: original.factBudget, finalSchema: original.finalSchema, finalBudget: original.finalBudget)
        let access = ParentReferenceFixtureService(plan: plan)
        let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: "", access: access)
        #expect(!result.ready && !result.complete)
        #expect(result.attempts.count == 6 && result.attempts.allSatisfy { !$0.result.dispatched })
        let count = await access.requests.count
        #expect(count == 0)
    }

    @Test(arguments: [ParentReferenceFixtureService.Mode.shared, .separate, .emptyParent])
    func productionAllowsIndependentOrSharedReferencesAndDoesNotRequireEmptyParents(_ mode: ParentReferenceFixtureService.Mode) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = ParentReferenceFixtureService(plan: plan, mode: mode)
        let diagnostics = S08ExtractionDiagnostics()
        let executor = ReportBatchExecutor(plan: plan, credential: "",
            access: S08ParentFactAccess(upstream: access, diagnostics: diagnostics),
            redact: { $0 }, progress: { _ in }, onRejection: { diagnostics.reject($0) })
        var parents: [Int: ReportFactNode] = [:]
        for step in plan.extraction where [15, 16].contains(step.id) {
            parents[step.id] = try await executor.execute(step, upstream: [:])
        }
        let target = try #require(plan.mergeLayers.first?.first { $0.id == 24 })
        let output = try await executor.execute(target, upstream: parents)
        #expect(!output.noRelevantContent && output.tokens <= 1_500)
        #expect(diagnostics.observation.rejections.isEmpty)
        let references = diagnostics.observation.groups?.flatMap(\.references)
        #expect(Set(references ?? []) == (mode == .emptyParent ? [16] : [15, 16]))
    }

    @Test(arguments: [ParentReferenceFixtureService.Mode.emptyParent, .missingParentTurn])
    func insufficientParentPreparationStartsNoMergeSamples(_ mode: ParentReferenceFixtureService.Mode) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = ParentReferenceFixtureService(plan: plan, mode: mode)
        let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: "", access: access)
        #expect(!result.ready && !result.complete)
        let parent = try #require(result.preparation.first { $0.node == 15 })
        #expect(parent.accepted == true && parent.retained == false && parent.observation.rejections.isEmpty)
        #expect(result.attempts.count == 6 && result.attempts.allSatisfy { !$0.result.dispatched && $0.result.accepted == nil })
        let merging = await access.requests.filter { if case .mergeFacts = $0.intent { true } else { false } }
        #expect(merging.isEmpty)
    }

    @Test(arguments: [ParentReferenceFixtureService.Mode.network, .association, .rawBudget, .malformed])
    func otherFailuresStopAndKeepUnsentSlotsWithoutCountingAsMissingParents(_ mode: ParentReferenceFixtureService.Mode) async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = ParentReferenceFixtureService(plan: plan, mode: mode)
        let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: "", access: access)
        #expect(result.ready && !result.complete && result.attempts.count == 6)
        let first = try #require(result.attempts.first?.result)
        #expect(first.dispatched && first.returned == (mode != .network))
        let accepted: Bool? = mode == .network ? nil : false
        #expect(first.accepted == accepted)
        let rejection: [ReportBatchExecutor.Rejection]
        switch mode {
        case .association: rejection = [.init(node: 24, predicate: .turnAssociation, fact: 0)]
        case .rawBudget: rejection = [.init(node: 24, predicate: .rawVisibleBudget, fact: nil)]
        case .malformed: rejection = [.init(node: 24, predicate: .payloadParsing, fact: nil)]
        default: rejection = []
        }
        #expect(first.observation.rejections == rejection)
        #expect(result.attempts.dropFirst().allSatisfy { !$0.result.dispatched && $0.result.accepted == nil })
        let count = await access.requests.count
        #expect(count == 3)
    }

    @Test func retainingBothParentReferencesDoesNotProveAllTurnsWereRetained() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let access = ParentReferenceFixtureService(plan: plan, mode: .numericOmission)
        let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: "", access: access)
        #expect(result.complete && result.attempts.allSatisfy { $0.result.accepted == true && $0.result.retained == false })
        #expect(result.attempts.allSatisfy { $0.result.observation.rejections.isEmpty })
    }

    @Test func theFullExecutorRecordsTheActualMissingNonemptyParentAndOnlyNumericTopology() async throws {
        let plan = try await makeOfflineS08LayeredPlan()
        let target = try #require(plan.mergeLayers.first?.first { $0.id == 24 })
        #expect(target.upstream == [15, 16])
        let service = ControlledAIService(), diagnostics = S08ExtractionDiagnostics()
        await service.enqueue(.success(missingParentPayload))
        let access = ParentReferenceTargetAccess(input: target.input,
            target: S08ParentFactAccess(upstream: service, diagnostics: diagnostics),
            other: S08CompactAIService(plan: plan))
        let executor = ReportBatchExecutor(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY", access: access,
            redact: { $0 }, progress: { _ in }, onRejection: { diagnostics.reject($0) })
        await #expect(throws: AIRequestError.invalidResponse) { try await executor.execute() }
        #expect(diagnostics.observation.rejections == [.init(node: 24, predicate: .nonemptyParents, fact: nil)])
        #expect(diagnostics.observation.covered == [15, 16])
        #expect(diagnostics.observation.groups == [.init(references: [16], status: 1, turns: [[[17, 1]]])])
        let encoded = String(decoding: try JSONEncoder().encode(diagnostics.observation), as: UTF8.self)
        #expect(!encoded.contains("SYNTHETIC_PRIVATE") && !encoded.contains("summary"))

        let fullRequest = try #require(await service.requests.first)
        var parents: [Int: ReportFactNode] = [:]
        for block in fullRequest.additionalInputs {
            let node = try JSONDecoder().decode(S08CompactNode.self, from: Data(block.utf8))
            let step = try #require(plan.extraction.first { $0.id == node.id })
            parents[node.id] = .init(id: node.id, coverage: Set(step.fragments.map(\.id)), block: block,
                tokens: try await OfflineReportTokenizer().count(block), noRelevantContent: node.noRelevantContent,
                redactionFailed: false)
        }
        let component = ControlledAIService(), componentDiagnostics = S08ExtractionDiagnostics()
        await component.enqueue(.success(missingParentPayload))
        let single = ReportBatchExecutor(plan: plan, credential: "SYNTHETIC_PRIVATE_KEY",
            access: S08ParentFactAccess(upstream: component, diagnostics: componentDiagnostics),
            redact: { $0 }, progress: { _ in }, onRejection: { componentDiagnostics.reject($0) })
        await #expect(throws: AIRequestError.invalidResponse) { try await single.execute(target, upstream: parents) }
        #expect(componentDiagnostics.observation == diagnostics.observation)
        let request = try #require(await component.requests.first)
        let identical = request.input == fullRequest.input && request.additionalInputs == fullRequest.additionalInputs
            && request.instruction == fullRequest.instruction && request.schema == fullRequest.schema
            && request.configuration == fullRequest.configuration && request.credential == fullRequest.credential
            && request.streaming == fullRequest.streaming
        #expect(identical)
    }

    private var missingParentPayload: String {
        #"{"covered":[15,16],"noRelevantContent":false,"groups":[{"references":[16],"status":"unconfirmed","facts":[{"turns":["17/1"],"summary":"SYNTHETIC_PRIVATE_SUMMARY"}]}]}"#
    }

}

actor ParentReferenceFixtureService {
    enum Mode: Sendable { case shared, separate, omission, emptyParent, missingParentTurn, network, association, rawBudget, malformed, numericOmission }
    let plan: ReportBatchPlan
    let mode: Mode
    private(set) var requests: [AIRequest] = []

    init(plan: ReportBatchPlan, mode: Mode = .shared) { self.plan = plan; self.mode = mode }

    func execute(_ request: AIRequest) async throws -> String {
        requests.append(request)
        var groups: [[String: Any]] = []
        let covered: [Int]
        if case .extractFacts = request.intent {
            let step = try #require(plan.extraction.first { $0.input == request.input })
            covered = step.fragments.map(\.id)
            groups = step.fragments.map { fragment in
                ["references": [fragment.id], "status": "unconfirmed", "facts": [
                    ["turns": [fragment.association], "summary": fragment.finalAnswer ?? "SYNTHETIC_PRIVATE_SUMMARY"]]]
            }
            if step.id == 15 && mode == .emptyParent { groups = [] }
            if step.id == 15 && mode == .missingParentTurn { groups = Array(groups.prefix(1)) }
        } else {
            if mode == .network { throw AIRequestError.network }
            if mode == .malformed { return "SYNTHETIC_PRIVATE_RAW" }
            covered = [15, 16]
            let omit = mode == .omission || mode == .emptyParent
            var turns = omit || mode == .numericOmission ? ["17/1"]
                : plan.extraction.filter { [15, 16].contains($0.id) }.flatMap(\.fragments).map(\.association)
            if mode == .association { turns = ["1/1"] }
            let summary = mode == .rawBudget ? String(repeating: " oversized", count: 1_600) : "SYNTHETIC_PRIVATE_SUMMARY"
            groups = [["references": omit ? [16] : [15, 16], "status": "unconfirmed", "facts": [
                ["turns": turns, "summary": summary]]]]
            if mode == .separate {
                groups = plan.extraction.filter { [15, 16].contains($0.id) }.map { step in
                    ["references": [step.id], "status": "unconfirmed", "facts": [
                        ["turns": step.fragments.map(\.association), "summary": summary]]]
                }
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject:
            ["covered": covered, "noRelevantContent": groups.isEmpty, "groups": groups]), as: UTF8.self)
    }
}

extension ParentReferenceFixtureService: AIServiceAccess {}

private struct ParentReferenceTargetAccess: AIServiceAccess {
    let input: String
    let target: any AIServiceAccess
    let other: any AIServiceAccess

    func execute(_ request: AIRequest) async throws -> String {
        try await (request.input == input ? target : other).execute(request)
    }
}
