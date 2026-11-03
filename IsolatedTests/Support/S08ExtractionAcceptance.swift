import Foundation
import Synchronization
@testable import random_thoughts

nonisolated enum S08ExtractionAcceptance {
    enum Status: String, Codable, Sendable { case unstarted, passed, rejected, incomplete }
    struct Node: Codable, Sendable {
        let node: Int
        let fragments: [Int]
        let expectedTurns: [[Int]]
        var dispatched = false
        var returned = false
        var accepted: Bool?
        var retained: Bool?
        var error: String?
        var userBytes = 0
        var answerBytes = 0
        var observation = S08ExtractionDiagnostics.Observation()
    }
    struct Round: Codable, Sendable {
        let repetition: Int
        var status: Status = .unstarted
        var error: String?
        var nodes: [Node]
    }
    struct Batch: Codable, Sendable {
        var admitted: Bool
        var rounds: [Round] = []
    }

    @MainActor
    static func run(plan: ReportBatchPlan, credential: String, access: any AIServiceAccess) async -> Batch {
        let planned = plan.extraction.map { step in
            Node(node: step.id, fragments: step.fragments.map(\.id),
                expectedTurns: Set(step.fragments.map { [$0.session, $0.order] }).sorted { $0.lexicographicallyPrecedes($1) })
        }
        var batch = Batch(admitted: false, rounds: (1...2).map { Round(repetition: $0, nodes: planned) })
        guard isOriginalBaseline(plan) else {
            batch.rounds[0].status = .incomplete
            batch.rounds[0].error = "baselineMismatch"
            return batch
        }
        for index in batch.rounds.indices {
            let roundAccess = S08ExtractionOnlyAccess(plan: plan, nodes: planned, upstream: access)
            var completed = false, error: String?
            do {
                _ = try await ReportBatchExecutor(plan: plan, credential: credential,
                    access: roundAccess,
                    redact: { $0 }, progress: { _ in },
                    onRejection: { roundAccess.reject($0) }).execute()
            } catch S08ExtractionStop.complete { completed = true }
            catch let caught { error = AIRequestError.reason(for: caught).rawValue }
            let nodes = roundAccess.snapshot(completed: completed)
            var round = Round(repetition: index + 1, status: .incomplete, error: error, nodes: nodes)
            if nodes.contains(where: { !$0.observation.rejections.isEmpty }) {
                round.status = .rejected
            } else if completed && nodes.allSatisfy({ $0.accepted == true && $0.retained != nil })
                && nodes.reduce(0, { $0 + $1.userBytes }) == 80_648
                && nodes.reduce(0, { $0 + $1.answerBytes }) == 6_833 {
                round.status = nodes.allSatisfy { $0.retained == true } ? .passed : .rejected
            }
            batch.rounds[index] = round
            guard round.status == .passed else { return batch }
        }
        batch.admitted = true
        return batch
    }

    private static func isOriginalBaseline(_ plan: ReportBatchPlan) -> Bool {
        let service = plan.prepared.context.service, configuration = service.configuration
        guard configuration.service == .responses, configuration.model == "gpt-6-luna",
              configuration.totalBudget == 9_550, configuration.outputLimit == 3_000, configuration.concurrency == 3,
              case .responses(let controls) = configuration.defaults,
              controls.reasoningEffort == AIReasoningEffort.none, controls.temperature == nil,
              service.validation.structured == .supported, service.validation.streaming == .supported,
              plan.visibleLimit == 1_500, plan.factBudget.limit == 5_240, plan.finalBudget.limit == 5_240,
              plan.factSchema == ReportFactPayload.schema, plan.factInstruction == plan.prepared.factInstruction,
              plan.extraction.map(\.id) == Array(1...16) else { return false }
        let fragments = plan.extraction.flatMap(\.fragments)
        return fragments.map(\.id) == Array(1...65)
            && Set(fragments.map { [$0.session, $0.order] }).count == 65
            && Set(fragments.map(\.session)).count == 17
            && fragments.reduce(0, { $0 + $1.user.utf8.count }) == 80_648
            && fragments.reduce(0, { $0 + ($1.finalAnswer?.utf8.count ?? 0) }) == 6_833
    }
}

private enum S08ExtractionStop: Error { case complete }

private final class S08ExtractionOnlyAccess: AIServiceAccess {
    let upstream: any AIServiceAccess
    let inputs: [String: Int]
    let diagnostics: [Int: S08ExtractionDiagnostics]
    let state: Mutex<[Int: S08ExtractionAcceptance.Node]>

    init(plan: ReportBatchPlan, nodes: [S08ExtractionAcceptance.Node], upstream: any AIServiceAccess) {
        self.upstream = upstream
        inputs = Dictionary(uniqueKeysWithValues: plan.extraction.map { ($0.input, $0.id) })
        diagnostics = Dictionary(uniqueKeysWithValues: nodes.map { ($0.node, S08ExtractionDiagnostics()) })
        state = Mutex(Dictionary(uniqueKeysWithValues: nodes.map { ($0.node, $0) }))
    }

    func execute(_ request: AIRequest) async throws -> String {
        guard case .extractFacts = request.intent else { throw S08ExtractionStop.complete }
        guard let id = inputs[request.input], let observer = diagnostics[id] else { throw AIRequestError.invalidResponse }
        let input = (try? JSONSerialization.jsonObject(with: Data(request.input.utf8))) as? [String: Any]
        let fragments = input?["fragments"] as? [[String: Any]] ?? []
        state.withLock { nodes in
            nodes[id]?.dispatched = true
            nodes[id]?.userBytes = fragments.reduce(0) { $0 + (($1["user"] as? String)?.utf8.count ?? 0) }
            nodes[id]?.answerBytes = fragments.reduce(0) { $0 + (($1["finalAnswer"] as? String)?.utf8.count ?? 0) }
        }
        do {
            let payload = try await S08ExtractionDiagnosticAccess(upstream: upstream, diagnostics: observer).execute(request)
            state.withLock { $0[id]?.returned = true }
            return payload
        } catch {
            state.withLock { $0[id]?.error = AIRequestError.reason(for: error).rawValue }
            throw error
        }
    }

    func reject(_ rejection: ReportBatchExecutor.Rejection) { diagnostics[rejection.node]?.reject(rejection) }

    func snapshot(completed: Bool) -> [S08ExtractionAcceptance.Node] {
        state.withLock { $0.values.sorted { $0.node < $1.node } }.map { value in
            var node = value
            node.observation = diagnostics[node.node]!.observation
            if !node.observation.rejections.isEmpty { node.accepted = false }
            else if completed && node.returned { node.accepted = true }
            if completed, let groups = node.observation.groups, node.observation.covered != nil {
                let turns = groups.flatMap(\.turns).flatMap { $0 }
                if turns.allSatisfy({ $0.count == 2 && !$0.contains(nil) }) {
                    let numbers = turns.map { $0.compactMap { $0 } }
                    node.retained = groups.contains { !$0.turns.isEmpty } && Set(numbers) == Set(node.expectedTurns)
                }
            }
            return node
        }
    }
}
