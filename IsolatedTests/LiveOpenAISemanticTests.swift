import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct LiveOpenAISemanticTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_LIVE_OPENAI"] == "1"))
    func officialOpenAIProtocols() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let key = variables["OPENAI_API_KEY"], !key.isEmpty,
              let output = variables["RANDOM_THOUGHTS_LIVE_OUTPUT"] else {
            throw LiveOpenAIError.missingEnvironment
        }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        var qualifiedServices: [SavedAIService] = []
        for service in [AIServiceType.chatCompletions, .responses] {
            let access = LiveOpenAIAccess(requestLimit: 3)
            let environment = ReportFlowTestEnvironment()
            environment.aiAccess = access
            let flow = environment.makeFlow()
            flow.send(.open(.report)); flow.send(.open(.settings))
            await flow.waitForStorage()
            flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(service))
            var edit = flow.aiServiceEdit
            edit.configuration = liveOpenAIConfiguration(service)
            edit.totalBudget = "65536"; edit.outputLimit = "3000"; edit.concurrency = "3"
            edit.newCredential = key
            flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService); await flow.waitForStorage()
            flow.send(.requestAIValidation); await flow.waitForAIValidation()
            let records = await access.records
            try JSONEncoder().encode(records).write(to: root.appendingPathComponent("\(service.rawValue)-probes.json"))
            let qualified = flow.savedAIService.hasMatchingValidation
            print("LIVE \(service.rawValue) probes=\(records.count) qualified=\(qualified) errors=\(records.compactMap(\.error))")
            #expect(qualified)
            guard qualified else { return }
            qualifiedServices.append(flow.savedAIService)
        }
        let mode = variables["RANDOM_THOUGHTS_LIVE_MODE"]
        guard mode == "scenarios" || mode == "invalid-response" || mode == "s07-plans" else { return }
        let scenarios = try ReportAcceptanceScenario.loadAll()
        let selected = qualifiedServices.flatMap { service in
            scenarios.filter { scenario in
                mode == "scenarios" || scenario.id == "S07"
                    || (mode == "invalid-response" && service.configuration.service == .chatCompletions && scenario.id == "S08")
            }.map { (service, $0) }
        }
        var plans: [String: LivePlan] = [:]
        for (service, scenario) in selected {
            let plan = try await LivePlan.make(scenario, service: service, credential: key)
            plans[plan.id] = plan
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plans).write(to: root.appendingPathComponent("plans.json"))
        let minimum = plans.values.reduce(0) { $0 + $1.minimumRequests * 2 }
        let maximum = plans.values.reduce(0) { $0 + $1.maximumRequests * 2 }
        print("LIVE PLAN generation HTTP=\(minimum)...\(maximum); tasks=\(selected.count * 2); no automatic retries")
        for (service, scenario) in selected {
            let plan = try #require(plans["\(service.configuration.service.rawValue)-\(scenario.id)"])
            for repetition in 1...2 {
                let id = "\(plan.id)-\(repetition)"
                let access = LiveOpenAIAccess(requestLimit: plan.maximumRequests)
                let environment = ReportFlowTestEnvironment()
                environment.aiAccess = access
                let flow = try await scenario.prepare(environment: environment, service: service)
                let started = Date()
                flow.send(.generateReport); await flow.waitForGeneration()
                if let confirmation = flow.confirmation {
                    // The user authorized this finite live acceptance run before any paid generation.
                    guard confirmation.generationScale?.maximumRequests == plan.maximumRequests else {
                        throw LiveOpenAIError.unexpectedConfiguration
                    }
                    flow.send(.confirm(confirmation.id)); await flow.waitForGeneration()
                }
                let requests = await access.records
                let result = environment.generationEvents.last
                let record = LiveTaskRecord(id: id, plan: plan, seconds: Date().timeIntervalSince(started),
                    error: flow.generationError?.rawValue, result: result?.result.rawValue ?? "unfinished",
                    actualPath: result?.path.rawValue ?? "planning", actualMergeLayers: result?.layer ?? 0,
                    historyDays: flow.generationSources?.historyDays.map(\.calendarDate) ?? [], requests: requests)
                try encoder.encode(record).write(to: root.appendingPathComponent("\(id).json"))
                if flow.hasDraft {
                    guard !flow.body.contains(key) else { throw LiveOpenAIError.unexpectedConfiguration }
                    // String's atomic writer may create an item-replacement directory outside this sandbox.
                    try Data(flow.body.utf8).write(to: root.appendingPathComponent("\(id).md"))
                }
                print("LIVE \(id) result=\(record.result) error=\(record.error ?? "none") HTTP=\(requests.count) layers=\(record.actualMergeLayers)")
                #expect(flow.hasDraft && flow.generationError == nil)
                if mode == "s07-plans" {
                    let plans = flow.body.components(separatedBy: "## 明日计划\n\n").last
                    // A verbatim source status in the wrong section is a degradation, not a new action.
                    // Other wording requires manual review; this is not a general semantic validator.
                    #expect(plans == "无明确内容" || plans == "- 四项隔离测试尚未执行。")
                }
                // Configuration/credit failures invalidate every dependent task; do not spend more on them.
                if let error = flow.generationError, error.invalidatesConfiguration || error == .quota || error == .serviceLimit { return }
            }
        }
    }
}

private enum LiveOpenAIError: Error { case missingEnvironment, unexpectedConfiguration }

private struct LivePlan: Codable {
    let id: String
    let totalBudget: Int
    let outputLimit: Int
    let inputLimit: Int
    let sessions: Int
    let turns: Int
    let userBytes: Int
    let answerBytes: Int
    let path: String
    let minimumRequests: Int
    let maximumRequests: Int
    let extractionRequests: Int
    let maximumMergeLayers: Int
    let fragments: Int
    let splitTurns: Int
    let auxiliaryClippedDuringExtraction: Bool

    @MainActor static func make(_ scenario: ReportAcceptanceScenario, service: SavedAIService, credential: String) async throws -> Self {
        var saved = service; saved.configuration.totalBudget = scenario.totalBudget
        let days = Set((1...max(1, scenario.settings.historyLookbackDays)).prefix(scenario.settings.historyLookbackDays).map {
            scenario.day.calendar.date(byAdding: .day, value: -$0, to: scenario.day.start)!
        })
        let context = ReportGenerationContext(service: saved,
            snapshot: .init(day: scenario.day, sessions: scenario.sessions, redactionFailed: false), settings: scenario.settings,
            history: scenario.history.filter { days.contains($0.day.start) }.sorted { $0.day.calendarDate > $1.day.calendarDate })
        let plan = try await ReportGenerationPlan.build(context, credential: credential, tokenizer: OfflineReportTokenizer(), redact: { $0 })
        let fragments: [ReportInputFragment]
        let clipped: Bool, path: String
        switch plan {
        case .direct: fragments = []; clipped = false; path = "direct"
        case .batched(let batch):
            fragments = batch.extraction.flatMap(\.fragments)
            clipped = batch.extraction.contains(where: \.auxiliaryClipped); path = "batched"
        }
        let difference = scenario.totalBudget - saved.configuration.outputLimit
        return .init(id: "\(saved.configuration.service.rawValue)-\(scenario.id)", totalBudget: scenario.totalBudget,
            outputLimit: saved.configuration.outputLimit, inputLimit: difference / 5 * 4 + difference % 5 * 4 / 5,
            sessions: scenario.sessions.count, turns: scenario.turns.count, userBytes: scenario.userBytes, answerBytes: scenario.answerBytes,
            path: path, minimumRequests: plan.scale.minimumRequests, maximumRequests: plan.scale.maximumRequests,
            extractionRequests: plan.scale.extractionRequests, maximumMergeLayers: plan.scale.mergeLayers,
            fragments: fragments.count, splitTurns: Set(fragments.filter { $0.parts > 1 }.map(\.association)).count,
            auxiliaryClippedDuringExtraction: clipped)
    }
}

private struct LiveTaskRecord: Codable {
    let id: String
    let plan: LivePlan
    let seconds: Double
    let error: String?
    let result: String
    let actualPath: String
    let actualMergeLayers: Int
    let historyDays: [String]
    let requests: [LiveOpenAIAccess.Record]
}

func liveOpenAIConfiguration(_ service: AIServiceType) -> AIServiceConfiguration {
    var configuration = AIServiceConfiguration(service: service)
    configuration.endpoint = service.endpointExample
    configuration.model = "gpt-5.4-mini-2026-03-17"
    configuration.outputLimit = 3_000
    switch service {
    case .chatCompletions: configuration.defaults = .chatCompletions(.init(reasoningEffort: AIReasoningEffort.none))
    case .responses: configuration.defaults = .responses(.init(reasoningEffort: AIReasoningEffort.none))
    case .messages: break
    }
    return configuration
}

private actor LiveOpenAIAccess: AIServiceAccess {
    struct Record: Codable, Sendable {
        let intent: String
        let inputTokens: Int
        let inputLimit: Int
        let backgroundUnits: Int
        let historyUnits: Int
        let fragments: Int
        let userBytes: Int
        let answerBytes: Int
        let seconds: Double
        let error: String?
    }
    private let client = AIServiceClient(transport: .production())
    private let requestLimit: Int
    private var dispatched = 0
    private(set) var records: [Record] = []
    init(requestLimit: Int) { self.requestLimit = requestLimit }

    func execute(_ request: AIRequest) async throws -> String {
        let configuration = request.configuration
        guard [.chatCompletions, .responses].contains(configuration.service),
              configuration.endpoint == configuration.service.endpointExample,
              configuration.model == "gpt-5.4-mini-2026-03-17", dispatched < requestLimit else { throw LiveOpenAIError.unexpectedConfiguration }
        dispatched += 1
        let intent: String
        switch request.intent {
        case .probe(let stage): intent = "probe-\(stage.rawValue)"
        case .extractFacts: intent = "extract"
        case .mergeFacts: intent = "merge"
        case .composeReport: intent = "compose"
        }
        let budget = try await ReportRequestBudget.make(instruction: request.instruction, schema: request.schema,
            configuration: configuration, tokenizer: OfflineReportTokenizer())
        let tokens = try await budget.count(request.input, blocks: request.additionalInputs)
        guard tokens <= budget.limit else { throw AIRequestError.budget }
        let input = (try? JSONSerialization.jsonObject(with: Data(request.input.utf8))) as? [String: Any]
        let background = (input?["background"] as? [Any])?.count ?? 0
        let history = (input?["historicalReports"] as? [Any])?.count ?? 0
        let fragments = (input?["fragments"] as? [[String: Any]]) ?? []
        let turns = fragments.isEmpty ? (input?["today"] as? [[String: Any]]) ?? [] : fragments
        let userBytes = turns.reduce(0) { $0 + (($1["user"] as? String)?.utf8.count ?? 0) }
        let answerBytes = turns.reduce(0) { $0 + (($1["finalAnswer"] as? String)?.utf8.count ?? 0) }
        let start = Date()
        do {
            let result = try await client.execute(request)
            records.append(.init(intent: intent, inputTokens: tokens, inputLimit: budget.limit,
                backgroundUnits: background, historyUnits: history, fragments: fragments.count, userBytes: userBytes, answerBytes: answerBytes,
                seconds: Date().timeIntervalSince(start), error: nil))
            return result
        } catch {
            records.append(.init(intent: intent, inputTokens: tokens, inputLimit: budget.limit,
                backgroundUnits: background, historyUnits: history, fragments: fragments.count, userBytes: userBytes, answerBytes: answerBytes,
                seconds: Date().timeIntervalSince(start), error: AIRequestError.reason(for: error).rawValue))
            throw error
        }
    }
}
