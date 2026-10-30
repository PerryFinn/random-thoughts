import Foundation
import Testing
@testable import random_thoughts

/// Executable form of docs/acceptance/issue-36/scenarios.md v1. Never loads expected answers.
@MainActor
struct ReportAcceptanceScenario {
    let id: String
    let settings: DailyReportGeneralSettings
    let sessions: [CodexCandidateSession]
    let history: [SavedDailyReport]
    let day: ReportDay
    var totalBudget: Int { ["S07", "S08", "S08-minimum", "S08-local"].contains(id) ? 12_000 : 65_536 }
    var turns: [CodexWorkTurn] { sessions.flatMap(\.turns) }
    var userBytes: Int { turns.reduce(0) { $0 + $1.userText.utf8.count } }
    var answerBytes: Int { turns.reduce(0) { $0 + ($1.finalAnswer?.utf8.count ?? 0) } }

    static func loadAll() throws -> [Self] {
        struct Seed: Decodable {
            let name: String
            let user: String
            let finalAnswer: String
            let background: String
            let history: String
        }
        let url = try #require(Bundle.module.url(forResource: "direct-report-semantics", withExtension: "json", subdirectory: "Fixtures"))
        let seeds = try JSONDecoder().decode([Seed].self, from: Data(contentsOf: url))
        let indexed = Dictionary(uniqueKeysWithValues: seeds.map { ($0.name, $0) })
        func seed(_ name: String) throws -> Seed {
            guard let value = indexed[name] else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
        let day = try ReportDay(calendarDate: "2026-10-20", timeZoneIdentifier: "Etc/UTC")
        func relative(_ offset: Int) -> ReportDay {
            ReportDay(date: day.calendar.date(byAdding: .day, value: offset, to: day.start)!, timeZone: day.timeZone)
        }
        func history(_ offset: Int, _ text: String) -> SavedDailyReport {
            .init(day: relative(offset), markdown: text, savedAt: day.start, lastEditedAt: nil)
        }
        var scenarios: [Self] = []
        for number in 1...8 {
            let id = String(format: "S%02d", number)
            var settings = DailyReportGeneralSettings()
            settings.timeZoneMode = .fixed
            settings.outputLanguage = [1, 4, 6, 8].contains(number) ? .english : .chinese
            settings.historyLookbackDays = [3, 8].contains(number) ? 2 : number == 4 ? 1 : 0
            var sessions: [CodexCandidateSession] = [], saved: [SavedDailyReport] = []
            var minute = 0, backgroundMinute = 0
            func session(_ name: String, _ pairs: [(String, String?)], background: [(String, String?)] = []) {
                func turn(_ pair: (String, String?), background: Bool) -> CodexWorkTurn {
                    let date = background ? relative(-1) : day
                    let index = background ? backgroundMinute : minute
                    if background { backgroundMinute += 1 } else { minute += 1 }
                    return .init(id: "\(id)-\(name)-\(background ? "background" : "today")-\(index)",
                        startedAt: date.start.addingTimeInterval(Double(9 * 3_600 + index * 60)), day: date,
                        userText: pair.0, finalAnswer: pair.1)
                }
                sessions.append(.init(id: "\(id)-\(name)", title: "\(id) synthetic \(name)", workDirectory: nil,
                    origin: .user, turns: pairs.map { turn($0, background: false) },
                    background: background.map { turn($0, background: true) }))
            }
            switch number {
            case 1:
                let source = try seed("english_completion")
                session("A", [(source.user, source.finalAnswer)])
                session("B", [("For the same synthetic settings document, add the agreed configuration table; do not publish it.",
                    "Added the configuration table to the same synthetic settings document. This is the same four-test run already reported, not four additional tests. No release was performed.")])
            case 2:
                let source = try seed("chinese_unconfirmed_conflict")
                session("A", [(source.user, source.finalAnswer)])
                session("B", [("请新增合成设置迁移说明并运行检查。", nil)])
            case 3:
                let source = try seed("chinese_completion")
                session("A", [("今天只复核昨天合成设置文档的术语，尚未执行新的测试，也未发布。",
                    "完成术语复核，未修改文档正文；今天没有新的测试或发布结果。")], background: [(source.user, source.finalAnswer)])
                saved = [history(-2, try seed("chinese_accepted_plan").history + "合成设置文档沿用代号 Alpha；两天前曾计划发布。"),
                         history(-3, "三天前计划做六项性能测试。")]
            case 4:
                let source = try seed("english_unconfirmed_conflict")
                session("A", [(source.user, source.finalAnswer)], background: [(source.background, nil)])
                session("B", [("The synthetic release note does not resolve whether Alpha means released. No follow-up action has been agreed.",
                    "The release status remains unconfirmed. " + (try seed("english_no_team_content").finalAnswer))])
                saved = [history(-1, source.history)]
            case 5:
                let source = try seed("chinese_accepted_plan")
                session("A", [(source.user.replacingOccurrences(of: "1970-01-02", with: "2026-10-22"), source.finalAnswer)],
                    background: [(source.history, nil)])
            case 6:
                let source = try seed("english_no_team_content")
                session("A", [(source.user, source.finalAnswer)])
            case 7:
                let source = try seed("chinese_unconfirmed_conflict")
                let user = source.user + "\n" + (1...1_024).map {
                    "SYNTH36-07-\(String(format: "%04d", $0))：仅复核合成格式，尚无新的完成证据；保留组合字符 é 与 👩🏽‍💻。\n"
                }.joined()
                let answer = "阶段性合成检查曾显示通过，但不是最终状态。\n" + (1...512).map {
                    "SYNTH36-07-复核-\(String(format: "%04d", $0))：仍需核对完整轮次，局部通过不等于发布完成。\n"
                }.joined() + "最终更正：完整合成校验失败，撤回阶段性通过结论；发布未完成，合成校验规则尚有错误。合成设置文档草稿已写完，四项隔离测试尚未执行。"
                session("A", [(user, answer)])
            case 8:
                let source = try seed("english_completion")
                session("A", [(source.user, source.finalAnswer)], background: [(String(repeating:
                    "SYNTH36-08 large background: terminology only; no evidence of today's delivery.\n", count: 512), nil)])
                for family in 1...16 {
                    let name = String(format: "B%02d", family)
                    let pairs: [(String, String?)] = (1...4).map { turn in
                        let item = "SYNTH36-08-\(name)-\(turn)"
                        let user = "For synthetic item \(item), document its distinct configuration rule and record its review state. Do not release.\n"
                            + (1...8).map { "\(item)-note-\($0): preserve this item's identity and review state; this synthetic note does not prove a release or any additional test.\n" }.joined()
                        var answer = "Drafted the configuration rule for \(item); its review is pending and it has not been released."
                        if family == 8 && turn == 4 { answer += " The shared synthetic schema mismatch blocks integrating these rules." }
                        if family == 16 && turn == 4 { answer += " The synthetic sign-off is still missing; release remains blocked." }
                        return (user, answer)
                    }
                    session(name, pairs, background: [("SYNTH36-08-\(name) refers to a distinct synthetic rule family; background only.", nil)])
                }
                saved = [history(-1, String(repeating: "SYNTH36-08 large history: a past release plan, not confirmed today.\n", count: 512)),
                         history(-2, try seed("english_accepted_plan").history)]
            default: preconditionFailure("Fixed eight scenarios only")
            }
            scenarios.append(.init(id: id, settings: settings, sessions: sessions, history: saved, day: day))
        }
        return scenarios
    }

    /// Three-turn reproducer of the S08 provenance/scope confusion; not a replacement for v1 acceptance.
    func blockerScopeMinimum(explicitlyLocal: Bool) throws -> Self {
        guard id == "S08" else { throw CocoaError(.fileReadCorruptFile) }
        let selected = sessions.filter { ["S08-B08", "S08-B16"].contains($0.id) }.map { session in
            let turns = session.turns.enumerated().filter {
                $0.offset == 3 || (session.id == "S08-B08" && $0.offset == 0)
            }.map { _, turn in
                CodexWorkTurn(id: turn.id, startedAt: turn.startedAt, day: turn.day,
                    userText: turn.userText.components(separatedBy: "\n")[0],
                    finalAnswer: explicitlyLocal ? turn.finalAnswer?.replacingOccurrences(
                        of: "The shared synthetic schema mismatch blocks integrating these rules.",
                        with: "Only SYNTH36-08-B08-4 is affected by the synthetic schema mismatch; the other rules are not affected. This mismatch blocks integration.") : turn.finalAnswer)
            }
            return CodexCandidateSession(id: session.id, title: session.title, workDirectory: session.workDirectory,
                origin: session.origin, turns: turns, background: [])
        }
        return Self(id: explicitlyLocal ? "S08-local" : "S08-minimum", settings: settings, sessions: selected, history: [], day: day)
    }

    func prepare(environment: ReportFlowTestEnvironment, service: SavedAIService) async throws -> DailyReportFlow {
        environment.now = day.start.addingTimeInterval(12 * 3_600)
        await environment.storage.setGeneralSettings(settings)
        for report in history { try await environment.storage.save(report) }
        var services = AIServiceSettings()
        var saved = service
        saved.configuration.totalBudget = totalBudget
        services.configurations[saved.configuration.service] = saved
        services.current = saved.configuration.service
        await environment.storage.setAISettings(services)
        let flow = try await prepareSessionFlow(environment, sessions: sessions)
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        return flow
    }
}
