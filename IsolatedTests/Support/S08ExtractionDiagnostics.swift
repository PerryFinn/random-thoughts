import Foundation
import Synchronization
@testable import random_thoughts

// Only the explicitly selected synthetic live component persists this projection.
// Neither these numbers nor projection failure participate in validation.
final class S08ExtractionDiagnostics: Sendable {
    struct Group: Codable, Equatable, Sendable {
        let references: [Int]
        // uncertain = 0, unconfirmed = 1, confirmed = 2.
        let status: Int
        let turns: [[[Int?]]]
    }
    struct Observation: Codable, Equatable, Sendable {
        var covered: [Int]?
        var groups: [Group]?
        var rejections: [ReportBatchExecutor.Rejection] = []
    }
    struct Attempt: Codable, Sendable {
        let repetition: Int
        let accepted: Bool
        let error: String?
        let observation: Observation
    }
    private let state = Mutex(Observation())
    var observation: Observation { state.withLock { $0 } }

    func observe(_ payload: String) {
        let projection = try? JSONDecoder().decode(Projection.self, from: Data(payload.utf8))
        let groups = projection?.groups.map { group in
            let status: Int
            switch group.status {
            case .uncertain: status = 0
            case .unconfirmed: status = 1
            case .confirmed: status = 2
            }
            return Group(references: group.references, status: status, turns: group.facts.map { fact in
                fact.turns.map { $0.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) } }
            })
        }
        state.withLock { $0.covered = projection?.covered; $0.groups = groups }
    }

    func reject(_ rejection: ReportBatchExecutor.Rejection) {
        state.withLock { $0.rejections.append(rejection) }
    }

    // Ignore summaries entirely; retain no free-text fields in the observation.
    private struct Projection: Decodable {
        struct Group: Decodable {
            struct Fact: Decodable { let turns: [String] }
            let references: [Int]
            let status: ReportFactPayload.Fact.Status
            let facts: [Fact]
        }
        let covered: [Int]
        let groups: [Group]
    }
}

struct S08ExtractionDiagnosticAccess: AIServiceAccess {
    let upstream: any AIServiceAccess
    let diagnostics: S08ExtractionDiagnostics

    func execute(_ request: AIRequest) async throws -> String {
        let payload = try await upstream.execute(request)
        if case .extractFacts = request.intent { diagnostics.observe(payload) }
        return payload
    }
}
