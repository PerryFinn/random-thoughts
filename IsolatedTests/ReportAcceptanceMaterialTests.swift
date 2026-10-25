import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportAcceptanceMaterialTests {
    @Test func preparedMaterialsDefineTheRequiredScalesAndSafeManualPrompts() throws {
        let material = try ReportAcceptanceMaterials.load()
        #expect(material.schemaVersion == 1 && material.seed == 35)
        #expect(material.reportDate == "2026-10-20" && material.timeZone == "Etc/UTC")
        #expect(material.scales.map(\.name) == ["small", "medium", "large"])
        #expect(material.scales.map(\.sessions) == [10, 100, 1_000])
        #expect(material.scales.map(\.turns) == [100, 1_000, 10_000])
        #expect(material.scales.map(\.utf8Bytes) == [1_048_576, 10_485_760, 104_857_600])
        #expect(material.scales.map(\.oversizedTurnBytes) == [0, 2_097_152, 2_097_152])
        #expect(material.codexPrompts.map(\.placement) == ["current", "archived"])
        #expect(material.codexPrompts.allSatisfy { !$0.prompt.isEmpty && !$0.allowedFacts.isEmpty && !$0.forbiddenConclusions.isEmpty })
        #expect(material.longParagraphRepeats == 80)
    }

    @Test func localStressMaterialsPreserveTheExactScalesDatesAndUnicode() throws {
        let material = try ReportAcceptanceMaterials.load()
        for scale in material.scales {
            let sessions = try material.makeSessions(for: scale)
            let turns = sessions.flatMap(\.turns)
            #expect(sessions.count == scale.sessions)
            #expect(Set(sessions.map(\.id)).count == scale.sessions)
            #expect(turns.count == scale.turns && Set(turns.map(\.id)).count == scale.turns)
            let sizes = turns.map { $0.userText.utf8.count + ($0.finalAnswer?.utf8.count ?? 0) }
            #expect(sizes.reduce(0, +) == scale.utf8Bytes)
            if scale.name != "small" { #expect(sizes.first == 2_097_152) }
            #expect(turns.allSatisfy {
                $0.day.calendarDate == "2026-10-20" && $0.day.timeZoneIdentifier == "Etc/UTC" &&
                $0.startedAt >= $0.day.start && $0.startedAt < $0.day.interval.end &&
                $0.userText.contains("Synthetic") && $0.userText.contains("仅合成") &&
                $0.userText.contains("```swift") && $0.userText.contains("é") && $0.userText.contains("👩🏽‍💻")
            })
        }
        let small = try #require(material.scales.first)
        #expect(try material.makeSessions(for: small) == material.makeSessions(for: small))
    }

    @Test func preparedSessionsConfirmThroughTheSharedFlowWithoutRealCodexOrAI() async throws {
        let material = try ReportAcceptanceMaterials.load()
        let sessions = try material.makeSessions(for: #require(material.scales.first))
        let environment = ReportFlowTestEnvironment()
        environment.now = try #require(sessions.first?.turns.first?.startedAt)
        let flow = try await prepareSessionFlow(environment, sessions: sessions)
        #expect(flow.sessionScan?.sessions.count == 10)
        #expect(flow.selectedSessionIDs.count == 10)
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let snapshot = try #require(flow.confirmedSnapshot)
        #expect(snapshot.sessions == sessions && snapshot.day == flow.selectedDay)
        #expect(!flow.isSourceDrawerVisible)
        flow.send(.showSources)
        flow.send(.selectAllSessions(false))
        #expect(flow.confirmedSnapshot == snapshot && flow.sourceSelectionNeedsConfirmation)
        #expect(await environment.codex.scanCount == 1)
        #expect(await environment.ai.requests.isEmpty)
    }
}
