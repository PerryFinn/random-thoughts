import Foundation
import Observation

@MainActor
@Observable
final class ReportGenerationStore {
    private(set) var activeDay: ReportDay?
    private(set) var lastDay: ReportDay?
    private(set) var stage: ReportGenerationStage = .planning
    private(set) var startedAt: Date?
    private(set) var error: AIRequestError?
    private(set) var retryAt: Date?
    private(set) var redactionFailed = false
    private var revision: UInt64 = 0
    private var runningService: SavedAIService?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let access: any AIServiceAccess
    @ObservationIgnored private let credentials: any AICredentialAccess
    @ObservationIgnored private let tokenizer: any ReportTokenCounting
    @ObservationIgnored private let redact: @Sendable (String) throws -> String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let record: (ReportGenerationEvent) -> Void

    init(access: any AIServiceAccess, credentials: any AICredentialAccess, tokenizer: any ReportTokenCounting,
         redact: @escaping @Sendable (String) throws -> String, now: @escaping () -> Date,
         record: @escaping (ReportGenerationEvent) -> Void) {
        self.access = access; self.credentials = credentials; self.tokenizer = tokenizer
        self.redact = redact; self.now = now; self.record = record
    }

    func wait() async { await task?.value }
    func fail(_ failure: AIRequestError, day: ReportDay) { lastDay = day; error = failure }
    func cancel() {
        guard activeDay != nil else { return }
        revision += 1; task?.cancel(); activeDay = nil; runningService = nil; error = .cancelled; retryAt = nil
        record(.init(kind: .finished, stage: stage, result: .cancelled, inputTokens: 0, error: .cancelled))
    }
    func clear() { cancel(); lastDay = nil; error = nil; retryAt = nil; redactionFailed = false }
    func configurationChanged(_ settings: AIServiceSettings) {
        guard activeDay != nil, let running = runningService,
              let saved = settings.configurations[running.configuration.service] else { return }
        let old = running.requestBaseline, new = saved.requestBaseline
        if settings.current != running.configuration.service || !old.endpoint.utf8.elementsEqual(new.endpoint.utf8)
            || !old.model.utf8.elementsEqual(new.model.utf8) || old.defaults != new.defaults
            || old.credentialVersion != new.credentialVersion {
            cancel()
        }
    }

    func start(_ context: ReportGenerationContext, completion: @escaping (ReportGenerationResult?, AIRequestError?) -> Void) {
        guard activeDay == nil else { return }
        revision += 1
        let operation = revision
        let day = context.snapshot.day
        activeDay = day; lastDay = day; startedAt = now(); stage = .planning; error = nil; retryAt = nil; redactionFailed = false
        runningService = context.service
        record(.init(kind: .started, stage: .planning, result: .running, inputTokens: 0, error: nil))
        task = Task {
            do {
                guard let envelope = context.service.credential else { throw AIRequestError.missingConfiguration }
                let credential = try await credentials.open(envelope)
                let plan = try await ReportInputPlan.build(context, credential: credential, tokenizer: tokenizer, redact: redact)
                guard !Task.isCancelled, revision == operation else { return }
                stage = .composing; redactionFailed = plan.redactionFailed
                record(.init(kind: .stageChanged, stage: stage, result: .running, inputTokens: plan.estimatedTokens, error: nil))
                let payload = try await access.execute(AIRequest(intent: .composeReport, configuration: context.service.configuration,
                    credential: credential, instruction: plan.instruction, input: plan.input, schema: plan.schema,
                    streaming: context.service.validation.streaming == .supported))
                let accepted = try await ReportPayload.maskAndRender(payload, language: context.settings.outputLanguage,
                                                                    credential: credential, redact: redact)
                guard !Task.isCancelled, revision == operation else { return }
                activeDay = nil; runningService = nil; redactionFailed = plan.redactionFailed || accepted.redactionFailed
                completion(.init(markdown: accepted.markdown, sources: plan.sources, redactionFailed: redactionFailed), nil)
                record(.init(kind: .finished, stage: stage, result: plan.auxiliaryClipped || redactionFailed ? .degraded : .success,
                             inputTokens: plan.estimatedTokens, error: nil))
            } catch {
                guard !Task.isCancelled, revision == operation else { return }
                let failure = error is AICredentialError ? .missingConfiguration : AIRequestError.reason(for: error)
                activeDay = nil; runningService = nil; self.error = failure
                retryAt = (error as? AIRequestFailure)?.retryAt
                completion(nil, failure)
                record(.init(kind: .finished, stage: stage, result: .failure, inputTokens: 0, error: failure))
            }
        }
    }
}
