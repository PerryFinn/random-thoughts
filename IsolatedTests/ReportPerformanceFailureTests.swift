import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportPerformanceFailureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_PERFORMANCE_SCALE"] != nil))
    func necessaryFailureAndLateCancellationStopTheCompletePressurePlan() async throws {
        let material = try ReportAcceptanceMaterials.load()
        let name = ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_PERFORMANCE_SCALE"]
        let scale = try #require(material.scales.first { $0.name == name })
        let sessions = try material.makeSessions(for: scale)
        let context = try ReportPerformanceMeasurement.context(sessions: sessions, concurrency: 3)
        guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: "",
            tokenizer: OfflineReportTokenizer(), redact: CredentialRedaction.redact) else { throw AIRequestError.budget }
        try #require(plan.extraction.count >= 3)
        for necessaryFailure in [true, false] {
            let access = BatchAIService(holds: true, ignoresCancellation: !necessaryFailure)
            let execution = Task {
                try await ReportBatchExecutor(plan: plan, credential: "", access: access,
                    redact: CredentialRedaction.redact, progress: { _ in }).execute()
            }
            await access.waitForRequests(3)
            if necessaryFailure { await access.release(0, failure: .network) }
            else {
                execution.cancel()
                // Deliver success after cancellation, including adapters that cannot stop remotely.
                await access.releaseAll()
            }
            switch await execution.result {
            case .success: throw AIRequestError.invalidResponse
            case .failure(let error):
                try #require(AIRequestError.reason(for: error) == (necessaryFailure ? .network : .cancelled))
            }
            try #require(await access.requests.count == 3)
            if necessaryFailure { try #require(await access.cancelled == 2) }
            // No subsequent extraction, merge or composition is dispatched.
            try #require(await access.requests.allSatisfy { if case .extractFacts = $0.intent { true } else { false } })
        }
        struct Result: Encodable {
            let scale: String
            let necessaryFailure = "passed"
            let lateCancellation = "passed"
            let dispatchedPerCase = 3
        }
        print("ISSUE35_CHECK " + String(decoding: try JSONEncoder().encode(Result(scale: scale.name)), as: UTF8.self))
    }
}
