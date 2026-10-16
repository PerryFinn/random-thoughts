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
    case planning, awaitingConfirmation, extracting, merging, composing
    var title: String {
        switch self {
        case .planning: "离线规划完整输入"
        case .awaitingConfirmation: "等待确认完整生成计划"
        case .extracting: "提取有据事实"
        case .merging: "整合全部片段与事实"
        case .composing: "生成六章节日报"
        }
    }
}

nonisolated struct ReportGenerationScale: Equatable, Sendable {
    let minimumRequests: Int
    let maximumRequests: Int
    let extractionRequests: Int
    let mergeLayers: Int
    var requiresConfirmation: Bool { maximumRequests > 4 }
    var description: String {
        let count = minimumRequests == maximumRequests ? "\(maximumRequests)" : "\(minimumRequests)–\(maximumRequests)"
        return "计划 \(count) 次请求 · 提取 \(extractionRequests) 次 · 最多 \(mergeLayers) 层归并 · 最终成文 1 次"
    }
}

nonisolated struct ReportGenerationEvent: Sendable {
    enum Kind: String, Sendable { case started = "report_generation_started", stageChanged = "report_generation_stage_changed", finished = "report_generation_finished" }
    enum Result: String, Sendable { case running, success, degraded, failure, cancelled }
    let kind: Kind
    let stage: ReportGenerationStage
    let result: Result
    let inputTokens: Int
    let error: AIRequestError?
    enum Path: String, Sendable { case planning, direct, batched }
    var path: Path = .planning
    var scale: ReportGenerationScale? = nil
    var layer = 0
    var completedRequests = 0
    var inFlightRequests = 0
}
