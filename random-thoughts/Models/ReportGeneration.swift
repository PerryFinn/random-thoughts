import Foundation

nonisolated struct ReportGenerationContext: Equatable, Sendable {
    let service: SavedAIService
    let snapshot: CodexSessionSnapshot
    let settings: DailyReportGeneralSettings
    let history: [SavedDailyReport]
}

nonisolated struct ReportGenerationSources: Sendable {
    struct Group: Identifiable, Sendable {
        let directory: String?
        let titles: [String]
        var id: String { directory ?? "" }
        var title: String { directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未归类" }
    }
    let groups: [Group]
    let historyDays: [ReportDay]
}

nonisolated struct ReportGenerationResult: Sendable {
    let markdown: String
    let sources: ReportGenerationSources
    let redactionFailed: Bool
}

nonisolated enum ReportGenerationStage: String, Sendable {
    case planning, composing
    var title: String { self == .planning ? "离线规划完整输入" : "生成六章节日报" }
}

nonisolated struct ReportGenerationEvent: Sendable {
    enum Kind: String, Sendable { case started = "report_generation_started", stageChanged = "report_generation_stage_changed", finished = "report_generation_finished" }
    enum Result: String, Sendable { case running, success, degraded, failure, cancelled }
    let kind: Kind
    let stage: ReportGenerationStage
    let result: Result
    let inputTokens: Int
    let error: AIRequestError?
}
