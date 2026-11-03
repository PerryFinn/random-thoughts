import Foundation
import Synchronization
@testable import random_thoughts

nonisolated enum S08ParentReferenceDiagnostics {
    struct Record: Codable, Sendable {
        let node: Int
        let references: [Int]
        let expectedTurns: [[Int]]
        var dispatched = false
        var returned = false
        var accepted: Bool?
        var retained: Bool?
        var normalizedTokens: Int?
        var error: String?
        var observation = S08ExtractionDiagnostics.Observation()
    }
    struct Attempt: Codable, Sendable {
        let repetition: Int
        var result: Record
    }
    struct Batch: Codable, Sendable {
        var ready = false
        var complete = false
        var preparation: [Record] = []
        var attempts: [Attempt] = []
    }

    @MainActor
    static func run(plan: ReportBatchPlan, credential: String, access: any AIServiceAccess) async -> Batch {
        guard let target = plan.mergeLayers.first?.first(where: { $0.id == 24 && $0.upstream == [15, 16] }) else { return Batch() }
        let steps = plan.extraction.filter { target.upstream.contains($0.id) }
        var batch = Batch(preparation: steps.map { record($0, plan: plan) },
            attempts: (1...6).map { .init(repetition: $0, result: record(target, plan: plan)) })
        guard S08ExtractionAcceptance.isOriginalBaseline(plan) else { return batch }
        var parents: [Int: ReportFactNode] = [:]
        await withTaskGroup(of: (Record, ReportFactNode?).self) { group in
            for step in steps {
                group.addTask { await execute(step, upstream: [:], plan: plan, credential: credential, access: access) }
            }
            for await (result, node) in group {
                if let index = batch.preparation.firstIndex(where: { $0.node == result.node }) {
                    batch.preparation[index] = result
                }
                if let node, result.accepted == true, result.retained == true,
                   result.observation.groups != nil, result.observation.covered != nil { parents[node.id] = node }
                else { group.cancelAll() }
            }
        }
        guard parents.count == 2 else { return batch }
        batch.ready = true
        for index in batch.attempts.indices {
            let (result, _) = await execute(target, upstream: parents, plan: plan, credential: credential, access: access)
            batch.attempts[index].result = result
            let targetRejection = result.observation.rejections == [.init(node: 24, predicate: .nonemptyParents, fact: nil)]
            guard result.returned && (result.accepted == true || targetRejection),
                  result.observation.groups != nil, result.observation.covered != nil else { return batch }
        }
        batch.complete = true
        return batch
    }

    private static func record(_ step: ReportBatchNodePlan, plan: ReportBatchPlan) -> Record {
        let fragments = step.fragments.isEmpty
            ? plan.extraction.filter { step.upstream.contains($0.id) }.flatMap(\.fragments) : step.fragments
        return Record(node: step.id, references: step.fragments.isEmpty ? step.upstream : step.fragments.map(\.id),
            expectedTurns: Set(fragments.map { [$0.session, $0.order] }).sorted { $0.lexicographicallyPrecedes($1) })
    }

    private static func execute(_ step: ReportBatchNodePlan, upstream: [Int: ReportFactNode],
                                plan: ReportBatchPlan, credential: String, access: any AIServiceAccess) async -> (Record, ReportFactNode?) {
        var result = record(step, plan: plan)
        let diagnostics = S08ExtractionDiagnostics()
        let observer = S08ParentFactAccess(upstream: access, diagnostics: diagnostics)
        let executor = ReportBatchExecutor(plan: plan, credential: credential, access: observer,
            redact: { $0 }, progress: { _ in }, onRejection: { diagnostics.reject($0) })
        var node: ReportFactNode?
        do {
            let output = try await executor.execute(step, upstream: upstream)
            node = output
            result.accepted = true; result.normalizedTokens = output.tokens
            if let normalized = try? JSONDecoder().decode(S08CompactNode.self, from: Data(output.block.utf8)) {
                let expected = Set(result.expectedTurns.map { "\($0[0])/\($0[1])" })
                result.retained = !normalized.noRelevantContent && Set(normalized.completeTurns) == expected
            }
        } catch {
            result.error = AIRequestError.reason(for: error).rawValue
            if !diagnostics.observation.rejections.isEmpty { result.accepted = false }
        }
        let state = observer.state.withLock { $0 }
        result.dispatched = state.dispatched; result.returned = state.returned
        result.observation = diagnostics.observation
        return (result, node)
    }
}

final class S08ParentFactAccess: AIServiceAccess {
    let upstream: any AIServiceAccess
    let diagnostics: S08ExtractionDiagnostics
    let state = Mutex((dispatched: false, returned: false))

    init(upstream: any AIServiceAccess, diagnostics: S08ExtractionDiagnostics) {
        self.upstream = upstream; self.diagnostics = diagnostics
    }

    func execute(_ request: AIRequest) async throws -> String {
        switch request.intent {
        case .extractFacts, .mergeFacts: break
        default: throw AIRequestError.parameters
        }
        state.withLock { $0.dispatched = true }
        let payload = try await upstream.execute(request)
        state.withLock { $0.returned = true }
        diagnostics.observe(payload)
        return payload
    }
}
