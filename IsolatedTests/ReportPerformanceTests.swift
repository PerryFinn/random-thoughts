import Dispatch
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_PERFORMANCE_SCALE"] != nil))
    func offlineStageMeasuresFirstAndRepeatedExecution() async throws {
        let variables = ProcessInfo.processInfo.environment
        let material = try ReportAcceptanceMaterials.load()
        let scale = try #require(material.scales.first { $0.name == variables["RANDOM_THOUGHTS_PERFORMANCE_SCALE"] })
        let stage = try #require(variables["RANDOM_THOUGHTS_PERFORMANCE_STAGE"])
        try #require(["scan", "tokenize", "plan", "schedule"].contains(stage))
        let concurrency = Int(variables["RANDOM_THOUGHTS_PERFORMANCE_CONCURRENCY"] ?? "3") ?? 0
        try #require([1, 3, 8].contains(concurrency))
        let sessions = try material.makeSessions(for: scale)
        try #require(sessions.count == scale.sessions)
        try #require(sessions.reduce(0) { $0 + $1.turns.count } == scale.turns)
        try #require(sessions.flatMap(\.turns).reduce(0) { $0 + $1.userText.utf8.count + ($1.finalAnswer?.utf8.count ?? 0) } == scale.utf8Bytes)
        let context = try ReportPerformanceMeasurement.context(sessions: sessions, concurrency: concurrency)
        let tokenizer = OfflineReportTokenizer()
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let reader: CodexDataSourceReader? = stage == "scan"
            ? try scanReader(environment, fixture: ReportAcceptanceMaterials.wireFixture(sessions: sessions)) : nil
        let identity = try scanIdentity(environment)
        var preparedPlan: ReportBatchPlan?
        if stage == "schedule" {
            let start = DispatchTime.now().uptimeNanoseconds
            let before = try ReportPerformanceSample.peakRSS()
            guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: "",
                tokenizer: tokenizer, redact: CredentialRedaction.redact) else { throw AIRequestError.budget }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            preparedPlan = plan
            try ReportPerformanceMeasurement.checkCoverage(plan, sessions: sessions)
            try await sample("schedule-setup", "first", elapsed, before, plan: plan).emit()
        }
        for iteration in ["first", "repeat"] {
            let before = try ReportPerformanceSample.peakRSS()
            let start = DispatchTime.now().uptimeNanoseconds
            var tokens = 0
            var measuredPlan: ReportBatchPlan?
            var access: PerformanceAIService?
            switch stage {
            case "scan":
                let result = try await #require(reader).scan(identity, day: context.snapshot.day, progress: { _ in })
                let matches = result.sessions == sessions
                try #require(matches && result.failures.isEmpty)
                try expectScanChildReaped(environment)
            case "tokenize":
                for session in sessions {
                    for turn in session.turns {
                        tokens += try await tokenizer.count(turn.userText)
                        if let final = turn.finalAnswer { tokens += try await tokenizer.count(final) }
                    }
                }
                try #require(tokens > 0)
            case "plan":
                guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: "",
                    tokenizer: tokenizer, redact: CredentialRedaction.redact) else { throw AIRequestError.budget }
                measuredPlan = plan
            case "schedule":
                let plan = try #require(preparedPlan)
                let service = PerformanceAIService(tokenizer: tokenizer)
                let output = try await ReportBatchExecutor(plan: plan, credential: "", access: service,
                    redact: CredentialRedaction.redact, progress: { _ in }).execute()
                _ = try ReportPayload.render(output.payload, language: .chinese)
                access = service
                measuredPlan = plan
            default: throw AIRequestError.parameters
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let result = try await sample(stage, iteration, elapsed, before, plan: measuredPlan, access: access, tokens: tokens)
            // Coverage checks are outside the stage clock and RSS endpoint.
            if let plan = measuredPlan {
                try ReportPerformanceMeasurement.checkCoverage(plan, sessions: sessions)
                if let access {
                    try #require(await access.extractedFragments == Set(plan.extraction.flatMap(\.fragments).map(\.id)))
                    try #require(await access.requests <= plan.scale.maximumRequests)
                    try #require(await access.maximumInFlight <= concurrency)
                }
            }
            try result.emit()
        }

        func sample(_ stageName: String, _ iteration: String, _ elapsed: Double, _ before: Int,
                    plan: ReportBatchPlan? = nil, access: PerformanceAIService? = nil, tokens: Int = 0) async throws -> ReportPerformanceSample {
            .init(scale: scale.name, stage: stageName, sample: iteration, sessions: scale.sessions, turns: scale.turns,
                utf8Bytes: scale.utf8Bytes, concurrency: concurrency, totalBudget: 65_536, outputLimit: 16_384,
                inputLimit: 39_321, milliseconds: elapsed, peakRSSBeforeBytes: before,
                peakRSSAfterBytes: try ReportPerformanceSample.peakRSS(),
                childPeakRSSBytes: stageName == "scan" ? try ReportPerformanceSample.peakRSS(RUSAGE_CHILDREN) : nil,
                requests: await access?.requests ?? 0, maximumInputTokens: await access?.maximumInputTokens ?? 0,
                maximumInFlight: await access?.maximumInFlight ?? 0,
                plannedMaximumRequests: plan?.scale.maximumRequests ?? 0, plannedMergeLayers: plan?.mergeLayers.count ?? 0,
                tokenizerTokens: tokens)
        }
    }
}
