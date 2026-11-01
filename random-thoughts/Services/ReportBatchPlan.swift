import Foundation

nonisolated enum ReportPlanningError: Error { case requiresBatches }

nonisolated enum ReportGenerationPlan: Sendable {
    case direct(ReportInputPlan)
    case batched(ReportBatchPlan)

    @concurrent static func build(_ context: ReportGenerationContext, credential: String, tokenizer: any ReportTokenCounting,
                                 redact: @Sendable (String) throws -> String) async throws -> Self {
        let prepared = ReportPreparedInput.make(context, credential: credential, redact: redact)
        do { return .direct(try await ReportInputPlan.build(prepared, tokenizer: tokenizer)) }
        catch ReportPlanningError.requiresBatches { return .batched(try await ReportBatchPlan.build(prepared, tokenizer: tokenizer)) }
    }

    var scale: ReportGenerationScale {
        switch self {
        case .direct: .init(minimumRequests: 1, maximumRequests: 1, extractionRequests: 0, mergeLayers: 0)
        case .batched(let plan): plan.scale
        }
    }
}

nonisolated struct ReportInputFragment: Encodable, Sendable {
    let id: Int
    let session: Int
    let order: Int
    let date: String
    let timeZone: String
    let result: String
    let part: Int
    let parts: Int
    let user: String
    let finalAnswer: String?
    let association: String

    init(id: Int, turn: ReportInputTurn, part: Int, parts: Int, user: String, finalAnswer: String?) {
        self.id = id; session = turn.session; order = turn.order; date = turn.date; timeZone = turn.timeZone
        result = turn.result; self.part = part; self.parts = parts; self.user = user; self.finalAnswer = finalAnswer
        association = "\(turn.session)/\(turn.order)"
    }
}

nonisolated struct ReportBatchInput: Encodable, Sendable {
    let reportDate: String
    let reportTimeZone: String
    let visibleBudget: Int
    let upstream: [Int]
    let fragments: [ReportInputFragment]
    let background: [ReportInputTurn]
    let historicalReports: [ReportInputHistory]
}

nonisolated struct ReportBatchNodePlan: Sendable {
    let id: Int
    let upstream: [Int]
    let fragments: [ReportInputFragment]
    let input: String
    let auxiliaryClipped: Bool
}

nonisolated struct ReportBatchPlan: Sendable {
    let prepared: ReportPreparedInput
    let extraction: [ReportBatchNodePlan]
    let mergeLayers: [[ReportBatchNodePlan]]
    let visibleLimit: Int
    let factInstruction: String
    let factSchema: String?
    let factBudget: ReportRequestBudget
    let finalSchema: String?
    let finalBudget: ReportRequestBudget

    var scale: ReportGenerationScale {
        .init(minimumRequests: extraction.count + 1,
              maximumRequests: extraction.count + mergeLayers.reduce(1) { $0 + $1.count },
              extractionRequests: extraction.count, mergeLayers: mergeLayers.count)
    }

    func input(upstream: [Int] = [], fragments: [ReportInputFragment] = [], background: [ReportInputTurn] = [],
               history: [ReportInputHistory] = []) throws -> String {
        try Self.input(prepared, visibleLimit: visibleLimit, upstream: upstream, fragments: fragments, background: background, history: history)
    }

    private static func input(_ prepared: ReportPreparedInput, visibleLimit: Int, upstream: [Int] = [],
                              fragments: [ReportInputFragment] = [], background: [ReportInputTurn] = [],
                              history: [ReportInputHistory] = []) throws -> String {
        try ReportJSON.encode(ReportBatchInput(reportDate: prepared.context.snapshot.day.calendarDate,
            reportTimeZone: prepared.context.snapshot.day.timeZoneIdentifier, visibleBudget: visibleLimit,
            upstream: upstream, fragments: fragments, background: background, historicalReports: history))
    }

    static func build(_ prepared: ReportPreparedInput, tokenizer: any ReportTokenCounting) async throws -> Self {
        let configuration = prepared.context.service.configuration
        let factInstruction = prepared.factInstruction
        let structured = prepared.context.service.validation.structured == .supported
        let factSchema = structured ? ReportFactPayload.schema : nil
        let finalSchema = structured ? ReportPayload.schema : nil
        let factBudget = try await ReportRequestBudget.make(instruction: factInstruction, schema: factSchema, configuration: configuration, tokenizer: tokenizer)
        let finalBudget = try await ReportRequestBudget.make(instruction: prepared.batchFinalInstruction, schema: finalSchema, configuration: configuration, tokenizer: tokenizer)
        // Reserve room for at least two maximum-size nodes and metadata. O also
        // includes thinking; this is a separate visible-payload contract.
        let marker = try input(prepared, visibleLimit: configuration.outputLimit, upstream: [Int.max, Int.max])
        let markerCost = try await tokenizer.count(marker)
        let visibleLimit = min(configuration.outputLimit / 2,
            min(factBudget.limit - factBudget.fixed - markerCost, finalBudget.limit - finalBudget.fixed - markerCost) / 2)
        let minimumNode = try ReportJSON.encode(ReportFactNode.Input(id: 1,
            facts: [.init(references: [1], turns: ["1/1"], status: .uncertain, summary: "fact")],
            noRelevantContent: false, completeTurns: ["1/1"]))
        guard visibleLimit > (try await tokenizer.count(minimumNode)) else { throw AIRequestError.budget }

        @Sendable func extractionInput(_ fragments: [ReportInputFragment], _ background: [ReportInputTurn] = []) throws -> String {
            try input(prepared, visibleLimit: visibleLimit, fragments: fragments, background: background)
        }
        func fits(_ fragments: [ReportInputFragment]) async throws -> Bool {
            let minimumPayload = ReportFactPayload(covered: fragments.map(\.id), noRelevantContent: true, facts: [])
            guard try await tokenizer.count(ReportJSON.encode(minimumPayload)) <= visibleLimit else { return false }
            return try await factBudget.count(extractionInput(fragments)) <= factBudget.limit
        }

        var batches: [[ReportInputFragment]] = [], current: [ReportInputFragment] = []
        var fragmentID = 1
        for session in Set(prepared.today.map(\.session)).sorted() {
            let turns = prepared.today.filter { $0.session == session }
            let wholeSession = turns.enumerated().map { offset, turn in
                ReportInputFragment(id: fragmentID + offset, turn: turn, part: 1, parts: 1, user: turn.user, finalAnswer: turn.finalAnswer)
            }
            if try await fits(current + wholeSession) { current += wholeSession; fragmentID += turns.count; continue }
            if !current.isEmpty { batches.append(current); current = [] }
            for turn in turns {
                try Task.checkCancellation()
                let whole = ReportInputFragment(id: fragmentID, turn: turn, part: 1, parts: 1, user: turn.user, finalAnswer: turn.finalAnswer)
                if try await fits(current + [whole]) { current.append(whole); fragmentID += 1; continue }
                if !current.isEmpty { batches.append(current); current = [] }
                if try await fits([whole]) { current = [whole]; fragmentID += 1; continue }

                var pieces: [(String, String?)] = []
                for (role, text) in [("user", turn.user), ("finalAnswer", turn.finalAnswer ?? "")] where !text.isEmpty {
                    let characters = Array(text)
                    var start = 0
                    while start < characters.count {
                        try Task.checkCancellation()
                        var lower = 1, upper = characters.count - start, count = 0
                        while lower <= upper {
                            let middle = lower + (upper - lower) / 2
                            let copy = String(characters[start..<(start + middle)])
                            let candidate = ReportInputFragment(id: Int.max, turn: turn, part: Int.max, parts: Int.max,
                                user: role == "user" ? copy : "", finalAnswer: role == "finalAnswer" ? copy : nil)
                            if try await fits([candidate]) { count = middle; lower = middle + 1 } else { upper = middle - 1 }
                        }
                        guard count > 0 else { throw AIRequestError.budget }
                        let copy = String(characters[start..<(start + count)])
                        pieces.append((role == "user" ? copy : "", role == "finalAnswer" ? copy : nil))
                        start += count
                    }
                }
                for (part, piece) in pieces.enumerated() {
                    let fragment = ReportInputFragment(id: fragmentID, turn: turn, part: part + 1, parts: pieces.count,
                        user: piece.0, finalAnswer: piece.1)
                    guard try await fits([fragment]) else { throw AIRequestError.budget }
                    batches.append([fragment]); fragmentID += 1
                }
            }
        }
        if !current.isEmpty { batches.append(current) }

        var extraction: [ReportBatchNodePlan] = []
        for (offset, fragments) in batches.enumerated() {
            let sessions = Set(fragments.map(\.session))
            let auxiliary = try await ReportAuxiliarySelection.build(background: prepared.background.filter { sessions.contains($0.session) },
                history: [], budget: factBudget, markerInput: extractionInput([]),
                evidence: { background, _ in try extractionInput(fragments, background) })
            extraction.append(.init(id: offset + 1, upstream: [], fragments: fragments, input: auxiliary.input, auxiliaryClipped: auxiliary.clipped))
        }
        var ids = extraction.map(\.id), nextID = ids.count + 1
        var layers: [[ReportBatchNodePlan]] = []
        func fitsNodes(_ group: [Int], budget: ReportRequestBudget) async throws -> Bool {
            let minimumPayload = ReportFactPayload(covered: group, noRelevantContent: true, facts: [])
            guard try await tokenizer.count(ReportJSON.encode(minimumPayload)) <= visibleLimit else { return false }
            let base = try await budget.count(input(prepared, visibleLimit: visibleLimit, upstream: group))
            return base <= budget.limit && group.count <= (budget.limit - base) / visibleLimit
        }
        while try await !fitsNodes(ids, budget: finalBudget) {
            try Task.checkCancellation()
            var groups: [[Int]] = [], group: [Int] = []
            for id in ids {
                if try await fitsNodes(group + [id], budget: factBudget) { group.append(id) }
                else {
                    guard group.count >= 2 else { throw AIRequestError.budget }
                    groups.append(group); group = [id]
                }
            }
            if !group.isEmpty { groups.append(group) }
            var layer: [ReportBatchNodePlan] = [], next: [Int] = []
            for group in groups {
                if group.count == 1 { next.append(group[0]); continue }
                layer.append(.init(id: nextID, upstream: group, fragments: [],
                    input: try input(prepared, visibleLimit: visibleLimit, upstream: group), auxiliaryClipped: false))
                next.append(nextID); nextID += 1
            }
            guard next.count < ids.count else { throw AIRequestError.budget }
            layers.append(layer); ids = next
        }
        return Self(prepared: prepared, extraction: extraction, mergeLayers: layers, visibleLimit: visibleLimit,
            factInstruction: factInstruction, factSchema: factSchema, factBudget: factBudget, finalSchema: finalSchema, finalBudget: finalBudget)
    }
}
