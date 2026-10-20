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
    private var path: ReportGenerationEvent.Path = .planning
    private(set) var scale: ReportGenerationScale?
    private var revision: UInt64 = 0
    private var runningService: SavedAIService?
    private struct Pending {
        let plan: ReportGenerationPlan
        let context: ReportGenerationContext
        let credential: String
        let completion: (ReportGenerationResult?, AIRequestError?) -> Void
    }
    private var pending: Pending?
    private(set) var completedRequests = 0
    private(set) var inFlightRequests = 0
    private(set) var layer = 0
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
        revision += 1; task?.cancel(); pending = nil; activeDay = nil; runningService = nil; inFlightRequests = 0; error = .cancelled; retryAt = nil
        emit(.init(kind: .finished, stage: stage, result: .cancelled, inputTokens: 0, error: .cancelled))
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

    var pendingContext: ReportGenerationContext? { pending?.context }

    func approvePlan() {
        guard let pending, activeDay != nil else { return }
        self.pending = nil
        let operation = revision
        task = Task { await execute(pending, operation: operation) }
    }

    func start(_ context: ReportGenerationContext, forceConfirmation: Bool = false,
               confirmation: @escaping (ReportGenerationScale) -> Void,
               completion: @escaping (ReportGenerationResult?, AIRequestError?) -> Void) {
        guard activeDay == nil else { return }
        revision += 1
        let operation = revision
        let day = context.snapshot.day
        activeDay = day; lastDay = day; startedAt = now(); stage = .planning; error = nil; retryAt = nil; redactionFailed = false
        path = .planning; scale = nil; completedRequests = 0; inFlightRequests = 0; layer = 0
        runningService = context.service
        emit(.init(kind: .started, stage: .planning, result: .running, inputTokens: 0, error: nil))
        task = Task {
            do {
                guard let envelope = context.service.credential else { throw AIRequestError.missingConfiguration }
                let credential = try await credentials.open(envelope)
                let plan = try await ReportGenerationPlan.build(context, credential: credential, tokenizer: tokenizer, redact: redact)
                guard !Task.isCancelled, revision == operation else { return }
                scale = plan.scale
                switch plan {
                case .batched(let plan): path = .batched; redactionFailed = plan.prepared.redactionFailed
                case .direct(let plan): path = .direct; redactionFailed = plan.redactionFailed
                }
                let prepared = Pending(plan: plan, context: context, credential: credential, completion: completion)
                if forceConfirmation || plan.scale.requiresConfirmation {
                    stage = .awaitingConfirmation; pending = prepared
                    confirmation(plan.scale)
                } else { await execute(prepared, operation: operation) }
            } catch { finish(error, operation: operation, completion: completion) }
        }
    }

    private func execute(_ pending: Pending, operation: UInt64) async {
        do {
            try Task.checkCancellation()
            let context = pending.context
            let payload: String, sources: ReportGenerationSources, clipped: Bool, masked: Bool
            switch pending.plan {
            case .direct(let plan):
                stage = .composing; redactionFailed = plan.redactionFailed; inFlightRequests = 1
                emit(.init(kind: .stageChanged, stage: stage, result: .running, inputTokens: plan.estimatedTokens, error: nil))
                try Task.checkCancellation()
                payload = try await access.execute(AIRequest(intent: .composeReport, configuration: context.service.configuration,
                    credential: pending.credential, instruction: plan.instruction, input: plan.input, schema: plan.schema,
                    streaming: context.service.validation.streaming == .supported))
                guard !Task.isCancelled, revision == operation else { return }
                completedRequests = 1; inFlightRequests = 0
                sources = plan.sources; clipped = plan.auxiliaryClipped; masked = plan.redactionFailed
            case .batched(let plan):
                let output = try await ReportBatchExecutor(plan: plan, credential: pending.credential, access: access, redact: redact,
                    progress: { update in
                        guard self.revision == operation, self.activeDay != nil else { return }
                        self.stage = update.stage; self.layer = update.layer
                        self.completedRequests = update.completed; self.inFlightRequests = update.inFlight
                        self.redactionFailed = self.redactionFailed || update.redactionFailed
                        self.emit(.init(kind: .stageChanged, stage: update.stage, result: .running, inputTokens: 0, error: nil))
                    }).execute()
                payload = output.payload; sources = output.sources; clipped = output.auxiliaryClipped; masked = output.redactionFailed
            }
            let accepted = try await ReportPayload.maskAndRender(payload, language: context.settings.outputLanguage,
                                                                credential: pending.credential, redact: redact)
            guard !Task.isCancelled, revision == operation else { return }
            activeDay = nil; runningService = nil; inFlightRequests = 0; redactionFailed = masked || accepted.redactionFailed
            pending.completion(.init(markdown: accepted.markdown, sources: sources, redactionFailed: redactionFailed), nil)
            emit(.init(kind: .finished, stage: stage, result: clipped || redactionFailed ? .degraded : .success, inputTokens: 0, error: nil))
        } catch { finish(error, operation: operation, completion: pending.completion) }
    }

    private func emit(_ event: ReportGenerationEvent) {
        var event = event
        event.path = path; event.scale = scale; event.layer = layer
        event.completedRequests = completedRequests; event.inFlightRequests = inFlightRequests
        record(event)
    }

    private func finish(_ error: any Error, operation: UInt64, completion: (ReportGenerationResult?, AIRequestError?) -> Void) {
        guard !Task.isCancelled, revision == operation else { return }
        let failure = error is AICredentialError ? .missingConfiguration : AIRequestError.reason(for: error)
        activeDay = nil; runningService = nil; pending = nil; inFlightRequests = 0; self.error = failure
        retryAt = (error as? AIRequestFailure)?.retryAt
        completion(nil, failure)
        emit(.init(kind: .finished, stage: stage, result: .failure, inputTokens: 0, error: failure))
    }
}
