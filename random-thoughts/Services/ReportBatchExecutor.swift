import Foundation

nonisolated struct ReportFactNode: Sendable {
    struct Input: Encodable {
        static let instructions = "Input nodes replace facts with ordered groups [{status,facts:[{turns,summary}]}]. Flatten groups in order; each fact inherits its group's status. Other node fields are unchanged."

        struct Group: Encodable {
            let status: ReportFactPayload.Fact.Status
            var facts: [ReportFactPayload.Evidence]
        }
        let id: Int
        let groups: [Group]
        let noRelevantContent: Bool
        let completeTurns: [String]

        init(id: Int, facts: [ReportFactPayload.Fact], noRelevantContent: Bool, completeTurns: [String]) {
            self.id = id
            var groups: [Group] = []
            for fact in facts {
                let evidence = ReportFactPayload.Evidence(turns: fact.turns, summary: fact.summary)
                if groups.last?.status == fact.status {
                    groups[groups.count - 1].facts.append(evidence)
                } else {
                    groups.append(Group(status: fact.status, facts: [evidence]))
                }
            }
            self.groups = groups
            self.noRelevantContent = noRelevantContent
            self.completeTurns = completeTurns
        }
    }
    let id: Int
    let coverage: Set<Int>
    let block: String
    let tokens: Int
    let noRelevantContent: Bool
    let redactionFailed: Bool
}

nonisolated struct ReportBatchProgress: Sendable {
    let stage: ReportGenerationStage
    let layer: Int
    let completed: Int
    let inFlight: Int
    var redactionFailed = false
}

nonisolated struct ReportBatchOutput: Sendable {
    let payload: String
    let sources: ReportGenerationSources
    let auxiliaryClipped: Bool
    let redactionFailed: Bool
}

nonisolated struct ReportBatchExecutor: Sendable {
    struct Rejection: Codable, Equatable, Sendable {
        enum Predicate: String, Codable, Sendable {
            case inputBudget, rawVisibleBudget, payloadParsing, coveredCount, coveredIDs, relevanceFlag
            case nonemptyParents, emptyReferences, duplicateReferences, referenceBounds
            case emptyTurns, duplicateTurns, emptySummary, turnAssociation, confirmedWholeTurn
            case normalizedVisibleBudget, strictReduction
        }
        let node: Int
        let predicate: Predicate
        let fact: Int?
    }

    let plan: ReportBatchPlan
    let credential: String
    let access: any AIServiceAccess
    let redact: @Sendable (String) throws -> String
    let progress: @MainActor @Sendable (ReportBatchProgress) -> Void
    var onRejection: @Sendable (Rejection) -> Void = { _ in }

    @concurrent func execute() async throws -> ReportBatchOutput {
        var completed = 0
        var nodes = try await run(plan.extraction, upstream: [:], layer: 0, completed: &completed)
        var clipped = plan.extraction.contains(where: \.auxiliaryClipped)
        var redactionFailed = plan.prepared.redactionFailed || nodes.contains(where: \.redactionFailed)
        for layer in 0...plan.mergeLayers.count {
            try Task.checkCancellation()
            let ordered = nodes.sorted { ($0.coverage.min() ?? 0) < ($1.coverage.min() ?? 0) }
            let blocks = ordered.map(\.block)
            let ids = ordered.map(\.id)
            let base = try plan.input(upstream: ids)
            if try await plan.finalBudget.count(base, blocks: blocks) <= plan.finalBudget.limit {
                let covered = nodes.reduce(into: Set<Int>()) { $0.formUnion($1.coverage) }
                let all = Set(plan.extraction.flatMap(\.fragments).map(\.id))
                guard covered == all else { throw AIRequestError.invalidResponse }
                let auxiliary = try await ReportAuxiliarySelection.build(background: [], history: plan.prepared.history,
                    budget: plan.finalBudget, markerInput: base, blocks: blocks,
                    evidence: { _, history in try plan.input(upstream: ids, history: history) })
                clipped = clipped || auxiliary.clipped
                await progress(.init(stage: .composing, layer: layer, completed: completed, inFlight: 1))
                try Task.checkCancellation()
                let payload = try await access.execute(request(intent: .composeReport, instruction: plan.prepared.batchFinalInstruction,
                    input: auxiliary.input, schema: plan.finalSchema, blocks: blocks))
                try Task.checkCancellation()
                completed += 1
                await progress(.init(stage: .composing, layer: layer, completed: completed, inFlight: 0))
                return .init(payload: payload, sources: plan.prepared.sources(historyDays: auxiliary.historyDays),
                    auxiliaryClipped: clipped, redactionFailed: redactionFailed)
            }
            guard layer < plan.mergeLayers.count else { throw AIRequestError.budget }
            let steps = plan.mergeLayers[layer]
            let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            let merged = try await run(steps, upstream: byID, layer: layer + 1, completed: &completed)
            let consumed = Set(steps.flatMap(\.upstream))
            let next = nodes.filter { !consumed.contains($0.id) } + merged
            guard next.count < nodes.count, next.reduce(0, { $0 + $1.tokens }) < nodes.reduce(0, { $0 + $1.tokens }) else {
                throw AIRequestError.budget
            }
            nodes = next
            redactionFailed = redactionFailed || merged.contains(where: \.redactionFailed)
        }
        throw AIRequestError.budget
    }

    private func request(intent: AIRequestIntent, instruction: String, input: String, schema: String?, blocks: [String] = []) -> AIRequest {
        AIRequest(intent: intent, configuration: plan.prepared.context.service.configuration, credential: credential,
            instruction: instruction, input: input, schema: schema,
            streaming: plan.prepared.context.service.validation.streaming == .supported, additionalInputs: blocks)
    }

    private func run(_ steps: [ReportBatchNodePlan], upstream: [Int: ReportFactNode], layer: Int,
                     completed: inout Int) async throws -> [ReportFactNode] {
        let concurrency = plan.prepared.context.service.configuration.concurrency
        guard (1...8).contains(concurrency) else { throw AIRequestError.parameters }
        return try await withThrowingTaskGroup(of: ReportFactNode.self) { group in
            var dispatched = 0, inFlight = 0
            var results: [ReportFactNode] = []
            func dispatch() async throws {
                try Task.checkCancellation()
                let step = steps[dispatched]
                dispatched += 1; inFlight += 1
                await progress(.init(stage: layer == 0 ? .extracting : .merging, layer: layer, completed: completed, inFlight: inFlight))
                try Task.checkCancellation()
                group.addTask { try await execute(step, upstream: upstream) }
            }
            do {
                for _ in 0..<min(concurrency, steps.count) { try await dispatch() }
                while let node = try await group.next() {
                    try Task.checkCancellation()
                    results.append(node); completed += 1; inFlight -= 1
                    await progress(.init(stage: layer == 0 ? .extracting : .merging, layer: layer, completed: completed,
                        inFlight: inFlight, redactionFailed: node.redactionFailed))
                    if dispatched < steps.count { try await dispatch() }
                }
                return results
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func execute(_ step: ReportBatchNodePlan, upstream: [Int: ReportFactNode]) async throws -> ReportFactNode {
        try Task.checkCancellation()
        func rejected(_ predicate: Rejection.Predicate, fact: Int? = nil, error: AIRequestError = .invalidResponse) -> AIRequestError {
            onRejection(.init(node: step.id, predicate: predicate, fact: fact))
            return error
        }
        let parents = try step.upstream.map { id in
            guard let node = upstream[id] else { throw AIRequestError.invalidResponse }
            return node
        }
        let blocks = parents.map(\.block)
        let fragments = plan.extraction.flatMap(\.fragments)
        let coverage = step.fragments.isEmpty ? parents.reduce(into: Set<Int>()) { $0.formUnion($1.coverage) } : Set(step.fragments.map(\.id))
        let wholeTurns = Set(Dictionary(grouping: fragments, by: \.association).compactMap { turn, parts in
            parts.allSatisfy { coverage.contains($0.id) } ? turn : nil
        })
        let schema = plan.factSchema.map { wholeTurns.isEmpty ? ReportFactPayload.partialTurnSchema : $0 }
        // The full schema reserves at least as much space as the restricted status enum.
        guard try await plan.factBudget.count(step.input, blocks: blocks) <= plan.factBudget.limit else {
            throw rejected(.inputBudget, error: .budget)
        }
        try Task.checkCancellation()
        let payload = try await access.execute(request(intent: step.fragments.isEmpty ? .mergeFacts : .extractFacts,
            instruction: plan.factInstruction, input: step.input, schema: schema, blocks: blocks))
        try Task.checkCancellation()
        guard try await plan.factBudget.tokenizer.count(payload) <= plan.visibleLimit else {
            throw rejected(.rawVisibleBudget, error: .budget)
        }
        var facts: ReportFactPayload
        do { facts = try ReportFactPayload.parse(payload) }
        catch {
            onRejection(.init(node: step.id, predicate: .payloadParsing, fact: nil))
            throw error
        }
        let expected = Set(step.fragments.isEmpty ? step.upstream : step.fragments.map(\.id))
        guard facts.covered.count == expected.count else { throw rejected(.coveredCount) }
        guard Set(facts.covered) == expected else { throw rejected(.coveredIDs) }
        guard facts.noRelevantContent == facts.facts.isEmpty else { throw rejected(.relevanceFlag) }
        let referenced = Set(facts.facts.flatMap(\.references))
        guard parents.filter({ !$0.noRelevantContent }).allSatisfy({ referenced.contains($0.id) }) else {
            throw rejected(.nonemptyParents)
        }
        let factTurns = Set(facts.facts.flatMap(\.turns))
        let completeTurns = factTurns.intersection(wholeTurns)
        var failed = false
        for index in facts.facts.indices {
            let fact = facts.facts[index]
            let references = Set(fact.references)
            guard !references.isEmpty else { throw rejected(.emptyReferences, fact: index) }
            guard references.count == fact.references.count else { throw rejected(.duplicateReferences, fact: index) }
            guard references.isSubset(of: expected) else { throw rejected(.referenceBounds, fact: index) }
            guard !fact.turns.isEmpty else { throw rejected(.emptyTurns, fact: index) }
            guard Set(fact.turns).count == fact.turns.count else { throw rejected(.duplicateTurns, fact: index) }
            guard !fact.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw rejected(.emptySummary, fact: index) }
            let citedCoverage = step.fragments.isEmpty
                ? parents.filter { references.contains($0.id) }.reduce(into: Set<Int>()) { $0.formUnion($1.coverage) }
                : references
            let citedTurns = Set(fragments.filter { citedCoverage.contains($0.id) }.map(\.association))
            guard Set(fact.turns).isSubset(of: citedTurns) else {
                throw rejected(.turnAssociation, fact: index)
            }
            if fact.status == .confirmed {
                guard fact.turns.allSatisfy({ turn in fragments.filter { $0.association == turn }.allSatisfy { citedCoverage.contains($0.id) } }) else {
                    throw rejected(.confirmedWholeTurn, fact: index)
                }
            }
            do { facts.facts[index].summary = try redact(fact.summary) } catch { failed = true }
            if !credential.isEmpty { facts.facts[index].summary = facts.facts[index].summary.replacingOccurrences(of: credential, with: "[已遮盖凭据]") }
        }
        let block = try ReportJSON.encode(ReportFactNode.Input(id: step.id, facts: facts.facts,
            noRelevantContent: facts.noRelevantContent, completeTurns: completeTurns.sorted()))
        let tokens = try await plan.factBudget.tokenizer.count(block)
        guard tokens <= plan.visibleLimit else { throw rejected(.normalizedVisibleBudget, error: .budget) }
        if !parents.isEmpty, tokens >= parents.reduce(0, { $0 + $1.tokens }) { throw rejected(.strictReduction, error: .budget) }
        return .init(id: step.id, coverage: coverage, block: block, tokens: tokens,
            noRelevantContent: facts.noRelevantContent, redactionFailed: failed)
    }
}
