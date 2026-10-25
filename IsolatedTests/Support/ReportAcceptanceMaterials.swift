import Foundation
import Testing
@testable import random_thoughts

struct ReportAcceptanceMaterials: Decodable {
    struct Scale: Decodable {
        let name: String
        let sessions: Int
        let turns: Int
        let utf8Bytes: Int
        let oversizedTurnBytes: Int
    }

    struct CodexPrompt: Decodable {
        let placement: String
        let prompt: String
        let allowedFacts: [String]
        let forbiddenConclusions: [String]
    }

    let schemaVersion: Int
    let seed: Int
    let reportDate: String
    let timeZone: String
    let codexPrompts: [CodexPrompt]
    let editorMarkdown: String
    let longParagraph: String
    let longParagraphRepeats: Int
    let scales: [Scale]

    static func load() throws -> Self {
        let url = try #require(Bundle.module.url(forResource: "acceptance-35", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func makeSessions(for scale: Scale) throws -> [CodexCandidateSession] {
        try #require(scale.sessions > 0 && scale.turns > 1 && scale.turns % scale.sessions == 0)
        let day = try ReportDay(calendarDate: reportDate, timeZoneIdentifier: timeZone)
        let turnsPerSession = scale.turns / scale.sessions
        let regularTurns = scale.turns - (scale.oversizedTurnBytes > 0 ? 1 : 0)
        let regularBytes = scale.utf8Bytes - scale.oversizedTurnBytes
        let finalAnswer = "仅合成结果：文档草案完成，验证未执行，发布未确认。"
        let chunk = longParagraph + "```swift\nlet syntheticSeed = \(seed)\n```\n"
        let chunkBytes = chunk.utf8.count

        return try (0..<scale.sessions).map { sessionIndex in
            let turns = try (0..<turnsPerSession).map { localIndex in
                let index = sessionIndex * turnsPerSession + localIndex
                let regularIndex = index - (scale.oversizedTurnBytes > 0 ? 1 : 0)
                let bytes = scale.oversizedTurnBytes > 0 && index == 0 ? scale.oversizedTurnBytes :
                    regularBytes / regularTurns + (regularIndex < regularBytes % regularTurns ? 1 : 0)
                let id = "SYNTH35-\(seed)-turn-\(index)"
                let prefix = "\(id)\n"
                let remaining = bytes - prefix.utf8.count - finalAnswer.utf8.count
                try #require(remaining >= chunkBytes)
                let text = prefix + String(repeating: chunk, count: remaining / chunkBytes) +
                    String(repeating: "x", count: remaining % chunkBytes)
                return CodexWorkTurn(id: id, startedAt: day.start.addingTimeInterval(Double(index)),
                                     day: day, userText: text, finalAnswer: finalAnswer)
            }
            return CodexCandidateSession(
                id: "SYNTH35-\(seed)-session-\(sessionIndex)",
                title: "仅合成会话 \(sessionIndex) " + String(repeating: "长标题 Unicode 👩🏽‍💻 / ", count: 6),
                workDirectory: "/synthetic/issue-35/worktree-\(sessionIndex % 3)",
                origin: .user, turns: turns, background: []
            )
        }
    }
}
