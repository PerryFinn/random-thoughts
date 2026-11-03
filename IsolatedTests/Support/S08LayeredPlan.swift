import Foundation
import Testing
@testable import random_thoughts

@MainActor
func makeOfflineS08LayeredPlan() async throws -> ReportBatchPlan {
    let source = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
    var configuration = AIServiceConfiguration(service: .responses)
    configuration.endpoint = "https://s08-offline.invalid"; configuration.model = "gpt-6-luna"
    configuration.totalBudget = 9_550; configuration.outputLimit = 3_000
    configuration.defaults = .responses(.init(reasoningEffort: AIReasoningEffort.none))
    var service = SavedAIService(configuration: configuration)
    service.validation.structured = .supported; service.validation.streaming = .supported
    let context = ReportGenerationContext(service: service,
        snapshot: .init(day: source.day, sessions: source.sessions, redactionFailed: false),
        settings: source.settings, history: source.history)
    guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: "",
        tokenizer: OfflineReportTokenizer(), redact: { $0 }) else { throw AIRequestError.budget }
    return plan
}
