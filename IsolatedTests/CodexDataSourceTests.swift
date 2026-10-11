import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct CodexDataSourceTests {
    @Test func storageFailureDoesNotCancelTheOldCheckOrReplaceItsCommittedSource() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        await environment.codex.holdNextCheck()
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await environment.codex.waitUntilCheckIsHeld()
        let saved = flow.codexSource
        var replacement = saved.configuration
        replacement.explicitDirectory = "/synthetic/rejected"
        flow.send(.editCodexSource(replacement, session: try #require(flow.openWindows[.settings])))
        await environment.storage.failSaves(true)
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        #expect(flow.codexSource == saved)
        #expect(flow.codexSourceEdit == replacement)
        #expect(flow.codexSourceStorageError == .writeFailed)
        #expect(flow.isCheckingCodexSource)
        #expect(environment.contextEffects == [.codexSourceChanged(revision: 1)])
        await environment.storage.failSaves(false)
        await environment.codex.releaseCheck()
        await flow.waitForCodexCheck()
        #expect(flow.codexSource.configuration == saved.configuration)
        #expect(flow.codexSourceStatus == .available)
        #expect(flow.codexSource.version?.description == "1.2.3")
        #expect(flow.hasCodexSourceEdits)
    }

    @Test func quittingCancelsTheCurrentCheckAndRejectsItsLateResult() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        await environment.codex.holdNextCheck()
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await environment.codex.waitUntilCheckIsHeld()
        var waiter: Task<Void, Never>?
        await withCheckedContinuation { started in
            waiter = Task { started.resume(); await flow.waitForCodexCheck() }
        }
        #expect(!flow.canTerminate)
        flow.send(.quit)
        #expect(environment.effects.last == .quit)
        #expect(flow.canTerminate)
        await environment.codex.releaseCheck()
        await waiter?.value
        #expect(flow.codexSourceStatus == .unchecked)
        #expect(flow.codexSource.lastSuccessfulCheck == nil)
        #expect(environment.codexEvents.map(\.result) == [.cancelled])
    }

    @Test func aFailedCheckKeepsTheCommittedSourceAndExistingReportAndDraft() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let reportSession = try #require(flow.openWindows[.report])
        let day = flow.selectedDay
        flow.send(.editBody("已保存 SYNTHETIC_REPORT_25", day: day, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        let savedReport = flow.savedReports[day]
        flow.send(.editBody("未保存 SYNTHETIC_DRAFT_25", day: day, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.open(.settings))
        flow.send(.requestSettingsPage(.dataSource))
        let configuration = CodexDataSourceConfiguration(mode: .manual, executablePath: "/synthetic/new", explicitDirectory: "/synthetic/selected")
        flow.send(.editCodexSource(configuration, session: try #require(flow.openWindows[.settings])))
        await environment.codex.failChecks(.methodUnsupported)
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        #expect(flow.codexSource.configuration == configuration)
        #expect(flow.codexSourceStatus == .unavailable)
        #expect(flow.codexSourceError == .methodUnsupported)
        #expect(flow.codexSource.lastSuccessfulCheck == nil)
        #expect(try await environment.storage.load().codexSource == flow.codexSource)
        #expect(flow.savedReports[day] == savedReport)
        #expect(flow.body == "未保存 SYNTHETIC_DRAFT_25")
        #expect(flow.hasDraft)
        #expect(environment.contextEffects == [.codexSourceChanged(revision: 1)])
    }

    @Test func replacingSourceRejectsLateDiagnosticsAndKeepsOnlyTheNewIdentity() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        await environment.codex.holdNextCheck()
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await environment.codex.waitUntilCheckIsHeld()
        var oldWaiter: Task<Void, Never>?
        await withCheckedContinuation { started in
            oldWaiter = Task {
                started.resume()
                await flow.waitForCodexCheck()
            }
        }
        let newConfiguration = CodexDataSourceConfiguration(mode: .manual, executablePath: "/synthetic/replacement", explicitDirectory: "/synthetic/replacement-home")
        flow.send(.editCodexSource(newConfiguration, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        await environment.codex.releaseCheck()
        await oldWaiter?.value
        #expect(flow.codexSource.configuration == newConfiguration)
        #expect(flow.codexSourceStatus == .available)
        #expect(flow.codexSource.version?.description == "9.8.7")
        #expect(try await environment.storage.load().codexSource == flow.codexSource)
        #expect(environment.contextEffects == [.codexSourceChanged(revision: 1), .codexSourceChanged(revision: 2)])
        #expect(environment.codexEvents.map(\.result) == [.cancelled, .success])
    }

    @Test func cancelledLeaveConfirmationKeepsCheckingButActualCloseRejectsLateSuccess() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        await environment.codex.holdNextCheck()
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await environment.codex.waitUntilCheckIsHeld()
        var oldWaiter: Task<Void, Never>?
        await withCheckedContinuation { started in
            oldWaiter = Task { started.resume(); await flow.waitForCodexCheck() }
        }
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.codexSourceEdit
        edit.explicitDirectory = "/synthetic/unsaved"
        flow.send(.editCodexSource(edit, session: session))
        flow.send(.requestCloseSettings(session))
        let obsolete = try #require(flow.confirmation?.id)
        edit.explicitDirectory = "/synthetic/revised"
        flow.send(.editCodexSource(edit, session: session))
        #expect(flow.confirmation?.id != obsolete)
        flow.send(.confirm(obsolete))
        #expect(flow.hasCodexSourceEdits)
        flow.send(.cancelConfirmation)
        #expect(flow.isCheckingCodexSource)
        flow.send(.requestCloseSettings(session))
        flow.send(.discardSettingsAndContinue(try #require(flow.confirmation?.id)))
        #expect(!flow.isCheckingCodexSource)
        #expect(flow.codexSourceStatus == .unchecked)
        #expect(environment.effects.last == .closeSettings(session: session))
        await environment.codex.releaseCheck()
        await oldWaiter?.value
        #expect(flow.codexSource.lastSuccessfulCheck == nil)
        #expect(flow.codexSource.version == nil)
        #expect(environment.codexEvents.map(\.result) == [.cancelled])
        flow.send(.windowClosed(.settings, session: session))
        flow.send(.open(.settings))
        flow.send(.editCodexSource(edit, session: session))
        #expect(!flow.hasCodexSourceEdits)
    }

    @Test func leavingEditedSourceUsesOneConfirmationAndStorageFailureKeepsThePage() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        let configuration = CodexDataSourceConfiguration(mode: .manual, executablePath: "/synthetic/manual", explicitDirectory: "/synthetic/other")
        flow.send(.editCodexSource(configuration, session: try #require(flow.openWindows[.settings])))
        #expect(!flow.canTerminate)
        flow.send(.requestSettingsPage(.general))
        #expect(flow.settingsPage == .dataSource)
        #expect(flow.confirmation?.windowKind == .settings)
        flow.send(.cancelConfirmation)
        #expect(flow.codexSourceEdit == configuration)
        await environment.storage.failSaves(true)
        flow.send(.requestSettingsPage(.general))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.codexSourceStorageError == .writeFailed)
        #expect(flow.settingsPage == .dataSource)
        #expect(flow.codexSource.configuration == CodexDataSourceConfiguration())
        #expect(flow.codexSourceEdit == configuration)
        #expect(await environment.codex.checkCount == 0)
        await environment.storage.failSaves(false)
        flow.send(.requestSettingsPage(.general))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        #expect(flow.settingsPage == .general)
        #expect(flow.codexSource.configuration == configuration)
        #expect(!flow.hasCodexSourceEdits)
    }

    @Test func savingAndCheckingKeepsAutomaticIdentityButRestartIsUnchecked() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        let session = try #require(flow.openWindows[.settings])
        let configuration = CodexDataSourceConfiguration(mode: .automatic, executablePath: "", explicitDirectory: "/synthetic/source")
        flow.send(.editCodexSource(configuration, session: session))
        flow.send(.saveCodexSource)
        await flow.waitForStorage()
        await flow.waitForCodexCheck()
        #expect(flow.codexSource.configuration.mode == .automatic)
        #expect(flow.codexSource.identity == CodexSourceIdentity(executablePath: "/synthetic/bin/codex", dataDirectory: "/synthetic/source"))
        #expect(flow.codexSourceStatus == .available)
        #expect(flow.codexSource.lastSuccessfulCheck == environment.now)
        #expect(flow.codexSource.version?.description == "9.8.7")
        let reopened = environment.makeFlow()
        reopened.send(.open(.settings))
        await reopened.waitForStorage()
        #expect(reopened.codexSource == flow.codexSource)
        #expect(reopened.codexSourceStatus == .unchecked)
        #expect(!reopened.isCheckingCodexSource)
        #expect(await environment.codex.checkCount == 1)
    }
}
