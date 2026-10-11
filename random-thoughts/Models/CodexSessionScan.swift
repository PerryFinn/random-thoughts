import Foundation

nonisolated enum CodexSessionOrigin: Sendable { case user, unknown }
nonisolated enum CodexScanActivity: Sendable { case waitingForSource, reading }

nonisolated struct CodexWorkTurn: Equatable, Sendable {
    let id: String
    let startedAt: Date
    let day: ReportDay
    let userText: String
    let finalAnswer: String?
    var isResultConfirmed: Bool { finalAnswer != nil }
}

nonisolated struct CodexCandidateSession: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let workDirectory: String?
    let origin: CodexSessionOrigin
    let turns: [CodexWorkTurn]
    let background: [CodexWorkTurn]
}

nonisolated struct CodexSessionFailure: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let workDirectory: String?
    let error: CodexSourceError
}

nonisolated struct CodexSessionScan: Equatable, Sendable {
    let sessions: [CodexCandidateSession]
    let failures: [CodexSessionFailure]
    let version: CodexVersion?
    var isPartial: Bool { !failures.isEmpty }
}

nonisolated struct CodexSessionSnapshot: Equatable, Sendable {
    let day: ReportDay
    let sessions: [CodexCandidateSession]
    let redactionFailed: Bool
}

nonisolated struct CodexSessionGroup: Identifiable, Sendable {
    let directory: String?
    let sessions: [CodexCandidateSession]
    var id: String { directory ?? "" }
    var title: String { directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未归类" }
}

nonisolated struct CodexScanEvent: Equatable, Sendable {
    enum Result: String, Sendable { case complete, partial, failure, cancelled }
    let result: Result
    let candidates: Int
    let succeeded: Int
    let failed: Int
}
