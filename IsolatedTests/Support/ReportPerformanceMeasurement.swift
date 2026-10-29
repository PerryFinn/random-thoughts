import Darwin
import Dispatch
import Foundation
import Testing
@testable import random_thoughts

struct ReportPerformanceSample: Encodable {
    let scale: String
    let stage: String
    let sample: String
    let sessions: Int
    let turns: Int
    let utf8Bytes: Int
    let concurrency: Int
    let totalBudget: Int
    let outputLimit: Int
    let inputLimit: Int
    let milliseconds: Double
    let peakRSSBeforeBytes: Int
    let peakRSSAfterBytes: Int
    let childPeakRSSBytes: Int?
    let requests: Int
    let maximumInputTokens: Int
    let maximumInFlight: Int
    let plannedMaximumRequests: Int
    let plannedMergeLayers: Int
    let tokenizerTokens: Int

    static func peakRSS(_ who: Int32 = RUSAGE_SELF) throws -> Int {
        var usage = rusage()
        guard getrusage(who, &usage) == 0 else { throw AIRequestError.unknown }
        return usage.ru_maxrss
    }

    func emit() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("ISSUE35_SAMPLE " + String(decoding: try encoder.encode(self), as: UTF8.self))
    }
}

// No transport, endpoint discovery, database, logger or stored request bodies.
// Empty synthetic facts measure the scheduler's mechanics, never semantic quality.
actor PerformanceAIService {
    private let tokenizer: OfflineReportTokenizer
    private(set) var requests = 0
    private(set) var maximumInputTokens = 0
    private(set) var maximumInFlight = 0
    private(set) var extractedFragments: Set<Int> = []
    private var inFlight = 0

    init(tokenizer: OfflineReportTokenizer) { self.tokenizer = tokenizer }

    func execute(_ request: AIRequest) async throws -> String {
        try Task.checkCancellation()
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        let configuration = request.configuration
        guard inFlight <= configuration.concurrency else { throw AIRequestError.parameters }
        var tokens = try await tokenizer.count(request.instruction) + 1_024
        for block in [request.input] + request.additionalInputs { tokens += try await tokenizer.count(block) }
        if let schema = request.schema {
            tokens += try await tokenizer.count(AIServiceClient.serializedFormat(schema, configuration: configuration))
        }
        maximumInputTokens = max(maximumInputTokens, tokens)
        guard tokens <= (configuration.totalBudget - configuration.outputLimit) * 4 / 5 else { throw AIRequestError.budget }
        requests += 1
        await Task.yield()
        try Task.checkCancellation()
        switch request.intent {
        case .composeReport:
            return #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#
        case .extractFacts, .mergeFacts:
            struct Input: Decodable {
                struct Fragment: Decodable { let id: Int }
                let fragments: [Fragment]
                let upstream: [Int]
            }
            let input = try JSONDecoder().decode(Input.self, from: Data(request.input.utf8))
            let ids = input.fragments.isEmpty ? input.upstream : input.fragments.map(\.id)
            for fragment in input.fragments {
                guard extractedFragments.insert(fragment.id).inserted else { throw AIRequestError.invalidResponse }
            }
            return try ReportJSON.encode(ReportFactPayload(covered: ids, noRelevantContent: true, facts: []))
        case .probe: throw AIRequestError.parameters
        }
    }
}

extension PerformanceAIService: AIServiceAccess {}

enum ReportPerformanceMeasurement {
    static func context(sessions: [CodexCandidateSession], concurrency: Int) throws -> ReportGenerationContext {
        var configuration = AIServiceConfiguration(service: .chatCompletions)
        configuration.totalBudget = 65_536
        configuration.outputLimit = 16_384
        configuration.concurrency = concurrency
        var service = SavedAIService(configuration: configuration)
        service.validation.structured = .supported
        return .init(service: service,
            snapshot: .init(day: try #require(sessions.first?.turns.first?.day), sessions: sessions, redactionFailed: false),
            settings: .init(), history: [])
    }

    static func checkCoverage(_ plan: ReportBatchPlan, sessions: [CodexCandidateSession]) throws {
        let fragments = plan.extraction.flatMap(\.fragments)
        try #require(Set(fragments.map(\.id)).count == fragments.count)
        let byTurn = Dictionary(grouping: fragments, by: \.association)
        try #require(byTurn.count == sessions.reduce(0) { $0 + $1.turns.count })
        for (sessionIndex, session) in sessions.enumerated() {
            for (turnIndex, turn) in session.turns.enumerated() {
                let pieces = try #require(byTurn["\(sessionIndex + 1)/\(turnIndex + 1)"]).sorted { $0.part < $1.part }
                try #require(pieces.map(\.part) == Array(1...pieces.count))
                try #require(pieces.allSatisfy { $0.parts == pieces.count })
                let userMatches = pieces.map(\.user).joined().utf8.elementsEqual(turn.userText.utf8)
                let finalMatches = pieces.compactMap(\.finalAnswer).joined().utf8.elementsEqual((turn.finalAnswer ?? "").utf8)
                try #require(userMatches && finalMatches)
            }
        }
        var nodes = Set(plan.extraction.map(\.id))
        for layer in plan.mergeLayers {
            let parents = layer.flatMap(\.upstream)
            try #require(Set(parents).count == parents.count && Set(parents).isSubset(of: nodes))
            try #require(layer.allSatisfy { $0.upstream.count >= 2 && !nodes.contains($0.id) })
            let next = nodes.subtracting(parents).union(layer.map(\.id))
            try #require(next.count < nodes.count)
            nodes = next
        }
    }
}
