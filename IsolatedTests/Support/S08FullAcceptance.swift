import Foundation
import Synchronization
@testable import random_thoughts

// Test-only ledger. Payloads and normalized blocks never enter the Codable state.
nonisolated enum S08FullAcceptance {
    enum Status: String, Codable, Sendable { case unstarted, passed, failed, incomplete }
    struct Node: Codable, Sendable {
        let id: Int
        let layer: Int
        let parents: [Int]
        let expectedTurns: [String]
        var dispatched = false
        var returned = false
        var accepted: Bool?
        var retained: Bool?
        var rawTokens: Int?
        var normalizedTokens: Int?
        var error: String?
        var observation = S08ExtractionDiagnostics.Observation()
    }
    struct Round: Codable, Sendable {
        let repetition: Int
        var status: Status = .unstarted
        var error: String?
        var issues: [String] = []
        var nodes: [Node]
        var composed = false
        var actualMergeLayers = 0
        var userBytes = 0
        var answerBytes = 0
        var backgroundUnits = 0
        var historyUnits = 0
        var auxiliaryClipped = false
    }
    struct Batch: Codable, Sendable {
        var passed = false
        let maximumHTTP: Int
        var rounds: [Round]
    }

    @MainActor
    static func run(plan: ReportBatchPlan, credential: String, access: any AIServiceAccess,
                    review: @escaping @Sendable (String, [ReportFactNode]) -> [String]) async -> Batch {
        var planned: [Node] = []
        for (layer, steps) in ([plan.extraction] + plan.mergeLayers).enumerated() {
            for step in steps {
                let turns = step.fragments.isEmpty
                    ? planned.filter { step.upstream.contains($0.id) }.flatMap(\.expectedTurns)
                    : step.fragments.map(\.association)
                planned.append(Node(id: step.id, layer: layer, parents: step.upstream, expectedTurns: Array(Set(turns)).sorted()))
            }
        }
        var batch = Batch(maximumHTTP: 3 + 2 * plan.scale.maximumRequests,
            rounds: (1...2).map { Round(repetition: $0, nodes: planned) })
        guard S08ExtractionAcceptance.isOriginalBaseline(plan), plan.scale.maximumRequests == 31,
              plan.mergeLayers.map(\.count) == [8, 4, 2] else {
            batch.rounds[0].status = .incomplete; batch.rounds[0].error = "baselineMismatch"
            return batch
        }
        for index in batch.rounds.indices {
            let observer = S08FullObservation(plan: plan, planned: batch.rounds[index], upstream: access)
            var complete = false, error: String?, issues: [String] = [], clipped = false
            do {
                let output = try await ReportBatchExecutor(plan: plan, credential: credential, access: observer,
                    redact: { $0 }, progress: { _ in }, onRejection: { observer.reject($0) },
                    onAcceptance: { observer.accept($0) }).execute()
                _ = try await ReportPayload.maskAndRender(output.payload, language: .english, credential: credential, redact: { $0 })
                clipped = output.auxiliaryClipped
                issues = review(output.payload, observer.acceptedNodes.withLock { $0 })
                complete = true
            } catch S08FullStop.evidence { }
            catch let caught { error = AIRequestError.reason(for: caught).rawValue }
            var round = observer.snapshot()
            if round.nodes.contains(where: { $0.retained == false }) { issues.append("turnRetention") }
            if round.composed && !complete && error == AIRequestError.reason(for: AIRequestError.invalidResponse).rawValue { issues.append("compositionPayload") }
            round.error = error; round.issues += issues; round.auxiliaryClipped = clipped
            if complete {
                if round.actualMergeLayers < 2 { round.issues.append("multiLayerCoverage") }
                if round.userBytes != 80_648 || round.answerBytes != 6_833 { round.issues.append("todayBytes") }
                if !clipped || round.backgroundUnits != 16 { round.issues.append("auxiliaryCoverage") }
                let used = round.nodes.filter(\.dispatched)
                if !used.allSatisfy({ $0.accepted == true && $0.retained == true }) { round.issues.append("nodeEvidence") }
            }
            if round.nodes.contains(where: { !$0.observation.rejections.isEmpty }) || !round.issues.isEmpty {
                round.status = .failed
            } else { round.status = complete ? .passed : .incomplete }
            batch.rounds[index] = round
            guard round.status == .passed else { return batch }
        }
        batch.passed = true
        return batch
    }
}

private enum S08FullStop: Error { case evidence }

private final class S08FullObservation: AIServiceAccess {
    let upstream: any AIServiceAccess
    let steps: [String: Int]
    let diagnostics: [Int: S08ExtractionDiagnostics]
    let state: Mutex<S08FullAcceptance.Round>
    let acceptedNodes = Mutex<[ReportFactNode]>([])

    init(plan: ReportBatchPlan, planned: S08FullAcceptance.Round, upstream: any AIServiceAccess) {
        self.upstream = upstream
        steps = Dictionary(uniqueKeysWithValues: (plan.extraction + plan.mergeLayers.flatMap { $0 }).map { ($0.input, $0.id) })
        diagnostics = Dictionary(uniqueKeysWithValues: planned.nodes.map { ($0.id, S08ExtractionDiagnostics()) })
        state = Mutex(planned)
    }

    func execute(_ request: AIRequest) async throws -> String {
        if state.withLock({ $0.nodes.contains { $0.retained == false } }) { throw S08FullStop.evidence }
        let input = (try? JSONSerialization.jsonObject(with: Data(request.input.utf8))) as? [String: Any] ?? [:]
        if case .composeReport = request.intent {
            let payload = try await upstream.execute(request)
            state.withLock { $0.composed = true; $0.historyUnits = (input["historicalReports"] as? [Any])?.count ?? 0 }
            return payload
        }
        guard let id = steps[request.input], let diagnostic = diagnostics[id] else { throw AIRequestError.invalidResponse }
        state.withLock { round in
            let index = round.nodes.firstIndex { $0.id == id }!
            round.nodes[index].dispatched = true
            round.actualMergeLayers = max(round.actualMergeLayers, round.nodes[index].layer)
            let fragments = (input["fragments"] as? [[String: Any]]) ?? []
            round.userBytes += fragments.reduce(0) { $0 + (($1["user"] as? String)?.utf8.count ?? 0) }
            round.answerBytes += fragments.reduce(0) { $0 + (($1["finalAnswer"] as? String)?.utf8.count ?? 0) }
            round.backgroundUnits += (input["background"] as? [Any])?.count ?? 0
        }
        do {
            let payload = try await upstream.execute(request)
            diagnostic.observe(payload)
            let tokens = try await OfflineReportTokenizer().count(payload)
            state.withLock { round in
                let index = round.nodes.firstIndex { $0.id == id }!
                round.nodes[index].returned = true; round.nodes[index].rawTokens = tokens
            }
            return payload
        } catch {
            state.withLock { round in
                round.nodes[round.nodes.firstIndex { $0.id == id }!].error = AIRequestError.reason(for: error).rawValue
            }
            throw error
        }
    }

    func reject(_ rejection: ReportBatchExecutor.Rejection) {
        diagnostics[rejection.node]?.reject(rejection)
        state.withLock { round in
            round.nodes[round.nodes.firstIndex { $0.id == rejection.node }!].accepted = false
        }
    }

    func accept(_ node: ReportFactNode) {
        acceptedNodes.withLock { $0.append(node) }
        let decoded = try? JSONDecoder().decode(S08CompactNode.self, from: Data(node.block.utf8))
        state.withLock { round in
            let index = round.nodes.firstIndex { $0.id == node.id }!
            round.nodes[index].accepted = true; round.nodes[index].normalizedTokens = node.tokens
            round.nodes[index].retained = decoded.map {
                !$0.facts.isEmpty && Set($0.facts.flatMap(\.turns)) == Set(round.nodes[index].expectedTurns)
            }
        }
    }

    func snapshot() -> S08FullAcceptance.Round {
        var round = state.withLock { $0 }
        for index in round.nodes.indices { round.nodes[index].observation = diagnostics[round.nodes[index].id]!.observation }
        return round
    }
}
