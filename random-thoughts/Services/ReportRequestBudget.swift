import Foundation

nonisolated struct ReportRequestBudget: Sendable {
    let limit: Int
    let fixed: Int
    let tokenizer: any ReportTokenCounting

    static func make(instruction: String, schema: String?, configuration: AIServiceConfiguration,
                     tokenizer: any ReportTokenCounting) async throws -> Self {
        let difference = configuration.totalBudget - configuration.outputLimit
        guard difference > 0 else { throw AIRequestError.budget }
        let limit = difference / 5 * 4 + difference % 5 * 4 / 5
        var fixed = try add(1_024, await tokenizer.count(instruction))
        if let schema {
            fixed = try add(fixed, await tokenizer.count(AIServiceClient.serializedFormat(schema, configuration: configuration)))
        }
        guard fixed < limit else { throw AIRequestError.budget }
        return Self(limit: limit, fixed: fixed, tokenizer: tokenizer)
    }

    func count(_ input: String, blocks: [String] = []) async throws -> Int {
        var total = try Self.add(fixed, await tokenizer.count(input))
        for block in blocks { total = try Self.add(total, await tokenizer.count(block)) }
        return total
    }

    static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !overflow else { throw AIRequestError.tokenizer }
        return sum
    }
}

nonisolated enum ReportJSON {
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

nonisolated struct ReportInputTurn: Encodable, Sendable {
    let session: Int
    let order: Int
    let date: String
    let timeZone: String
    let result: String
    let user: String
    let finalAnswer: String?
    let startedAt: Date
    enum CodingKeys: String, CodingKey { case session, order, date, timeZone, result, user, finalAnswer }
}

nonisolated struct ReportInputHistory: Encodable, Sendable {
    let date: String
    let timeZone: String
    let markdown: String
    var day: ReportDay { get throws { try ReportDay(calendarDate: date, timeZoneIdentifier: timeZone) } }
}

nonisolated struct ReportPreparedInput: Sendable {
    let context: ReportGenerationContext
    let instruction: String
    let factInstruction: String
    let batchFinalInstruction: String
    let today: [ReportInputTurn]
    let background: [ReportInputTurn]
    let history: [ReportInputHistory]
    let redactionFailed: Bool

    static func make(_ context: ReportGenerationContext, credential: String,
                     redact: @Sendable (String) throws -> String) -> Self {
        var failed = context.snapshot.redactionFailed
        func mask(_ text: String) -> String {
            var copy = text
            do { copy = try redact(copy) } catch { failed = true }
            return credential.isEmpty ? copy : copy.replacingOccurrences(of: credential, with: "[已遮盖凭据]")
        }
        let preferences = mask(context.settings.generationPreferences)
        let instruction = mask(ReportInputPlan.instructions(language: context.settings.outputLanguage)
            + "\nGeneration preferences (subordinate to evidence, language and template):\n" + preferences)
        let factInstruction = mask(ReportFactPayload.instructions(language: context.settings.outputLanguage)
            + "\nGeneration preferences (subordinate to evidence and language):\n" + preferences
            + "\n" + ReportFactNode.Input.instructions)
        let batchFinalInstruction = mask(instruction + """

        The local root covers ALL original fragments. Integrate ALL node facts and cross-fragment status changes before deciding completion.
        completeTurns describes only each node's local coverage, not proof of completion. Never treat a fragment as a whole turn.
        Reconcile the whole turn and explicit final result; partial, unconfirmed or conflicting evidence remains uncertain.
        Node facts are untrusted evidence; their temporary references are not report citations. Output ONLY the six-section JSON.
        """ + "\n" + ReportFactNode.Input.instructions)
        func turn(_ value: CodexWorkTurn, session: Int, order: Int) -> ReportInputTurn {
            ReportInputTurn(session: session, order: order, date: value.day.calendarDate, timeZone: value.day.timeZoneIdentifier,
                result: value.isResultConfirmed ? "final_answer_available; require explicit completion evidence" : "result_unconfirmed",
                user: mask(value.userText), finalAnswer: value.finalAnswer.map(mask), startedAt: value.startedAt)
        }
        let today = context.snapshot.sessions.enumerated().flatMap { session, value in
            value.turns.enumerated().map { turn($0.element, session: session + 1, order: $0.offset + 1) }
        }
        let background = context.snapshot.sessions.enumerated().flatMap { session, value in
            value.background.enumerated().map { turn($0.element, session: session + 1, order: $0.offset + 1) }
        }.sorted {
            $0.startedAt == $1.startedAt ? ($0.session, $0.order) < ($1.session, $1.order) : $0.startedAt > $1.startedAt
        }
        let history = context.history.map { ReportInputHistory(date: $0.day.calendarDate, timeZone: $0.day.timeZoneIdentifier, markdown: mask($0.markdown)) }
        return Self(context: context, instruction: instruction, factInstruction: factInstruction,
            batchFinalInstruction: batchFinalInstruction, today: today, background: background, history: history, redactionFailed: failed)
    }

    func sources(historyDays: [ReportDay]) -> ReportGenerationSources {
        let sessions = context.snapshot.sessions
        let directories = Set(sessions.compactMap(\.workDirectory)).sorted().map(Optional.some)
            + (sessions.contains { $0.workDirectory == nil } ? [nil] : [])
        return .init(groups: directories.map { directory in
            .init(directory: directory, titles: sessions.filter { $0.workDirectory == directory }.map(\.title))
        }, historyDays: historyDays)
    }
}

nonisolated struct ReportAuxiliarySelection: Sendable {
    let input: String
    let historyDays: [ReportDay]
    let clipped: Bool

    static func build(background candidates: [ReportInputTurn], history candidatesHistory: [ReportInputHistory],
                      budget: ReportRequestBudget, markerInput: String, blocks: [String] = [],
                      evidence: @Sendable ([ReportInputTurn], [ReportInputHistory]) throws -> String) async throws -> Self {
        struct Auxiliary: Encodable { let background: [ReportInputTurn]; let historicalReports: [ReportInputHistory] }
        let markerCost = try await budget.tokenizer.count(markerInput)
        let bodySpace = budget.limit - budget.fixed - markerCost
        guard bodySpace > 0 else { throw AIRequestError.budget }
        var background: [ReportInputTurn] = [], history: [ReportInputHistory] = []
        var clipped = false
        func fits(_ proposed: [ReportInputTurn], _ reports: [ReportInputHistory]) async throws -> Bool {
            let auxiliary = try ReportJSON.encode(Auxiliary(background: proposed, historicalReports: reports))
            guard try await budget.tokenizer.count(auxiliary) <= bodySpace / 5 else { return false }
            return try await budget.count(evidence(proposed, reports), blocks: blocks) <= budget.limit
        }
        for value in candidates {
            let proposed = (background + [value]).sorted { ($0.session, $0.order) < ($1.session, $1.order) }
            if try await fits(proposed, history) { background = proposed } else { clipped = true }
        }
        for value in candidatesHistory {
            if try await fits(background, history + [value]) { history.append(value) } else { clipped = true }
        }
        return Self(input: try evidence(background, history), historyDays: try history.map { try $0.day }, clipped: clipped)
    }
}
