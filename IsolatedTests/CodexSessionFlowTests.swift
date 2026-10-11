import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct CodexSessionFlowTests {
    @Test(arguments: [CodexSourceStatus.unchecked, .available], [CodexSourceError.scanLockTimedOut, .scanLockUnavailable])
    func lockFailuresShowAScanErrorWithoutChangingSourceAvailability(_ status: CodexSourceStatus, _ error: CodexSourceError) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow: DailyReportFlow
        if status == .available {
            flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("user")])
        } else {
            try await environment.storage.saveCodexSource(CodexDataSourceSettings(
                configuration: CodexDataSourceConfiguration(executablePath: "/synthetic/bin/codex"),
                resolvedDirectory: "/synthetic/.codex"))
            flow = environment.makeFlow()
            flow.send(.open(.report))
            await flow.waitForStorage()
        }
        #expect(flow.codexSourceStatus == status)
        await environment.codex.failScans(error)
        flow.send(.scanSessions)
        await flow.waitForSessionScan()
        #expect(flow.sessionScanError == error)
        #expect(flow.codexSourceStatus == status)
        #expect(flow.codexSourceError == nil)
        #expect(!flow.canConfirmSessionSelection)
    }

    @Test(arguments: [true, false])
    func scanningReplacesAnInFlightCheckAndRejectsItsLaterContradictoryResult(_ succeeds: Bool) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("user")])
        await environment.codex.holdNextCheck()
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await environment.codex.waitUntilCheckIsHeld()
        var oldCheck: Task<Void, Never>?
        await withCheckedContinuation { ready in
            oldCheck = Task { @MainActor in
                ready.resume()
                await flow.waitForCodexCheck()
            }
        }
        await environment.codex.failScans(succeeds ? nil : .schemaUnsupported)
        flow.send(.scanSessions)
        await flow.waitForSessionScan()
        #expect(!flow.isCheckingCodexSource)
        #expect(flow.codexSourceStatus == (succeeds ? .available : .unavailable))
        await environment.codex.releaseCheck(error: succeeds ? .methodUnsupported : nil)
        await oldCheck?.value
        #expect(flow.codexSourceStatus == (succeeds ? .available : .unavailable))
        #expect(flow.codexSourceError == (succeeds ? nil : .schemaUnsupported))
    }

    @Test func cancellingAScanKeepsSourceAvailabilityAndItsSnapshotAndShowsACancelledResult() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("old")])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let snapshot = flow.confirmedSnapshot
        await environment.codex.holdNextScan()
        flow.send(.scanSessions)
        await environment.codex.waitUntilScanIsHeld()
        flow.send(.cancelSessionScan)
        await environment.codex.releaseScan(CodexSessionScan(sessions: [], failures: [], version: nil))
        await flow.waitForSessionScan()
        #expect(flow.sessionScanError == .cancelled)
        #expect(flow.codexSourceStatus == .available)
        #expect(flow.confirmedSnapshot == snapshot)
        #expect(environment.scanEvents.last?.result == .cancelled)
    }

    @Test func changingTheSelectionInvalidatesAnEarlierUnknownSourceApproval() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("user"), syntheticCandidate("unknown", origin: .unknown)])
        flow.send(.selectAllSessions(true))
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.selectAllSessions(false))
        flow.send(.confirm(obsolete))
        #expect(flow.selectedSessionIDs.isEmpty)
        #expect(flow.confirmation == nil)
    }

    @Test func redactionFailureStillConfirmsAndKeepsSuccessfulRedactionsInOtherFields() async throws {
        enum Failure: Error { case synthetic }
        let environment = ReportFlowTestEnvironment()
        environment.redact = { text in
            if text == "MASK_FAILURE_26" { throw Failure.synthetic }
            return try CredentialRedaction.redact(text)
        }
        let day = ReportDay(date: environment.now, timeZone: .gmt)
        let candidate = CodexCandidateSession(id: "mask-failure", title: "会话", workDirectory: nil, origin: .user,
            turns: [CodexWorkTurn(id: "turn", startedAt: environment.now, day: day, userText: "MASK_FAILURE_26",
                                  finalAnswer: "sk-123456789012345678901234567890")], background: [])
        let flow = try await prepareSessionFlow(environment, sessions: [candidate])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let snapshot = try #require(flow.confirmedSnapshot)
        #expect(snapshot.redactionFailed)
        #expect(snapshot.sessions[0].turns[0].userText == "MASK_FAILURE_26")
        #expect(snapshot.sessions[0].turns[0].finalAnswer == "[已遮盖凭据]")
        #expect(!flow.isSourceDrawerVisible)
    }

    @Test func bulkAndGroupSelectionAskBeforeUnknownSourcesAndRefreshResetsTheirTrust() async throws {
        let environment = ReportFlowTestEnvironment()
        let user = syntheticCandidate("user")
        let unknown = syntheticCandidate("unknown", origin: .unknown, directory: nil)
        let flow = try await prepareSessionFlow(environment, sessions: [user, unknown])
        flow.send(.selectAllSessions(true))
        #expect(flow.selectedSessionIDs == ["user"])
        #expect(flow.confirmation != nil)
        flow.send(.cancelConfirmation)
        #expect(flow.selectedSessionIDs == ["user"])
        flow.send(.selectSessionGroup(nil, true))
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.confirm(obsolete))
        #expect(flow.selectedSessionIDs == ["user", "unknown"])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let original = try #require(flow.confirmedSnapshot)
        flow.send(.showSources)
        await environment.codex.setScan(CodexSessionScan(sessions: [syntheticCandidate("new"), unknown], failures: [], version: nil))
        flow.send(.scanSessions)
        await flow.waitForSessionScan()
        flow.send(.confirm(obsolete))
        #expect(flow.confirmedSnapshot == original)
        #expect(flow.selectedSessionIDs == ["new"])
        #expect(flow.sourceSelectionNeedsConfirmation)
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        #expect(flow.confirmedSnapshot?.sessions.map(\.id) == ["new"])
        #expect(await environment.codex.scanCount == 2)
    }

    @Test func savingANewSourceRejectsLateScansAndPreservesTheSnapshotDraftAndReport() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("old")])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let original = try #require(flow.confirmedSnapshot)
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("已保存", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        flow.send(.editBody("保留草稿", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        await environment.codex.holdNextScan()
        flow.send(.scanSessions)
        await environment.codex.waitUntilScanIsHeld()
        var source = flow.codexSourceEdit
        source.explicitDirectory = "/synthetic/new-source"
        flow.send(.editCodexSource(source, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        await environment.codex.releaseScan(CodexSessionScan(sessions: [syntheticCandidate("late")], failures: [], version: nil))
        await flow.waitForSessionScan()
        #expect(flow.sessionScan == nil)
        #expect(flow.selectedSessionIDs.isEmpty)
        #expect(flow.confirmedSnapshot == original)
        #expect(flow.body == "保留草稿")
        #expect(flow.savedReports[flow.selectedDay]?.markdown == "已保存")
        #expect(flow.codexSourceStatus == .available)
        #expect(environment.scanEvents.map(\.result) == [.complete, .cancelled])
    }

    @Test func actualCloseReleasesAllSourceMaterialAndRejectsTheOldWindowCallback() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("old")])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let session = try #require(flow.openWindows[.report])
        await environment.codex.holdNextScan()
        flow.send(.scanSessions)
        await environment.codex.waitUntilScanIsHeld()
        flow.send(.windowClosed(.report, session: session))
        flow.send(.open(.report))
        await environment.codex.releaseScan(CodexSessionScan(sessions: [syntheticCandidate("late")], failures: [], version: nil))
        await flow.waitForSessionScan()
        #expect(flow.confirmedSnapshot == nil)
        #expect(flow.sessionScan == nil)
        #expect(flow.selectedSessionIDs.isEmpty)
        #expect(!flow.isSourceDrawerVisible)
    }

    @Test func confirmingMasksHighConfidenceCredentialsAndKeepsOrdinaryNamesAndPaths() async throws {
        let environment = ReportFlowTestEnvironment()
        environment.redact = CredentialRedaction.redact
        let raw = "项目 Perry /work/project person@example.invalid\nAuthorization: Bearer SYNTHETIC_TOKEN_1234567890\napi_key=sk-123456789012345678901234567890\n-----BEGIN PRIVATE KEY-----\nSYNTHETIC_PRIVATE_KEY\n-----END PRIVATE KEY-----"
        let session = syntheticCandidate("redaction", user: raw)
        let flow = try await prepareSessionFlow(environment, sessions: [session])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let snapshot = try #require(flow.confirmedSnapshot)
        let text = snapshot.sessions[0].turns[0].userText
        #expect(text.contains("项目 Perry /work/project person@example.invalid"))
        #expect(!text.contains("SYNTHETIC_TOKEN"))
        #expect(!text.contains("sk-123"))
        #expect(!text.contains("SYNTHETIC_PRIVATE_KEY"))
        #expect(!snapshot.redactionFailed)
    }

    @Test func scanningSelectsUserSessionsAndConfirmationFreezesTheInputWithoutReadingAgain() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        let turn = CodexWorkTurn(id: "turn", startedAt: environment.now, day: flow.selectedDay,
                                 userText: "合成用户正文", finalAnswer: nil)
        let user = CodexCandidateSession(id: "user", title: "合成用户会话", workDirectory: "/synthetic/project",
                                         origin: .user, turns: [turn], background: [])
        let unknown = CodexCandidateSession(id: "unknown", title: "合成未知来源", workDirectory: nil,
                                            origin: .unknown, turns: [turn], background: [])
        await environment.codex.setScan(CodexSessionScan(sessions: [user, unknown], failures: [], version: nil))
        flow.send(.showSources)
        flow.send(.scanSessions)
        await flow.waitForSessionScan()
        #expect(flow.sessionScan?.sessions == [user, unknown])
        #expect(flow.selectedSessionIDs == ["user"])
        flow.send(.confirmSessionSelection)
        await flow.waitForSessionScan()
        let snapshot = try #require(flow.confirmedSnapshot)
        #expect(snapshot.day == flow.selectedDay)
        #expect(snapshot.sessions == [user])
        #expect(!flow.isSourceDrawerVisible)
        #expect(await environment.codex.scanCount == 1)
        flow.send(.showSources)
        flow.send(.selectAllSessions(false))
        #expect(flow.confirmedSnapshot == snapshot)
        #expect(flow.sourceSelectionNeedsConfirmation)
        #expect(await environment.codex.scanCount == 1)
    }
}

@MainActor
func prepareSessionFlow(_ environment: ReportFlowTestEnvironment, sessions: [CodexCandidateSession]) async throws -> DailyReportFlow {
    let flow = environment.makeFlow()
    flow.send(.open(.report))
    flow.send(.open(.settings))
    await flow.waitForStorage()
    flow.send(.requestSettingsPage(.dataSource))
    flow.send(.saveCodexSource)
    await flow.waitForStorage()
    await flow.waitForCodexCheck()
    await environment.codex.setScan(CodexSessionScan(sessions: sessions, failures: [], version: nil))
    flow.send(.showSources)
    flow.send(.scanSessions)
    await flow.waitForSessionScan()
    return flow
}

func syntheticCandidate(_ id: String, user: String = "合成工作", origin: CodexSessionOrigin = .user,
                        directory: String? = "/synthetic/project", day: ReportDay? = nil) -> CodexCandidateSession {
    let date = Date(timeIntervalSince1970: 1000)
    let day = day ?? ReportDay(date: date, timeZone: .gmt)
    return CodexCandidateSession(id: id, title: "合成 \(id)", workDirectory: directory, origin: origin,
                                 turns: [CodexWorkTurn(id: "turn-\(id)", startedAt: date, day: day, userText: user, finalAnswer: nil)], background: [])
}
