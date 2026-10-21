import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportContentManagementTests {
    @Test(arguments: [AppWindowKind.report, .settings])
    func openingAWindowDuringResetCannotReloadTheOldContent(_ window: AppWindowKind) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report)); flow.send(.open(.settings)); await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let day = flow.selectedDay
        flow.send(.editBody("重置前已保存正文", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save); await flow.waitForStorage()
        flow.send(.editBody("提交失败的草稿", day: day, session: session, revision: flow.reportEditRevision))
        await environment.storage.failSaves(true)
        flow.send(.save); flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.storageError == .writeFailed)
        await environment.storage.failSaves(false)
        flow.send(.requestSettingsPage(.contentManagement)); flow.send(.requestResetReportData)
        await environment.storage.holdNextSave()
        flow.send(.confirm(try #require(flow.confirmation).id))
        await environment.storage.waitUntilSaveIsHeld()
        #expect(flow.isSaving && !flow.isStorageReady)
        flow.send(.open(window))
        #expect(flow.storageError == .writeFailed)
        await environment.storage.releaseSave(); await flow.waitForStorage()
        #expect(flow.isStorageReady && !flow.isSaving)
        #expect(flow.contentCounts == ReportContentCounts(saved: 0, drafts: 0, snapshots: 0))
        #expect(try await environment.storage.load().reports.isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func deletionNeverAcceptsLateGenerationEvenWhenCommitFails(_ clearAll: Bool, _ commitFails: Bool) async throws {
        let environment = ReportFlowTestEnvironment(), access = BatchAIService(ignoresCancellation: true)
        environment.aiAccess = access
        try await installSyntheticAI(environment, totalBudget: 12_000, outputLimit: 3_000)
        let flow = try await prepareGeneratedLifecycleFlow(environment, batched: false)
        let day = flow.selectedDay
        flow.send(.save); await flow.waitForStorage()
        let saved = try #require(flow.savedReports[day])
        await access.hold(stage: .composing)
        try await beginHeldLifecycleGeneration(flow, access: access, stage: .composing)
        if clearAll {
            flow.send(.requestSettingsPage(.contentManagement)); flow.send(.requestClearReports)
        } else { flow.send(.requestDeleteReport(day)) }
        #expect(flow.activeGenerationDay == day)
        await environment.storage.failSaves(commitFails)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.activeGenerationDay == nil)
        await access.releaseAll(); await flow.waitForGeneration(); await flow.waitForStorage()
        #expect(!flow.hasDraft)
        #expect(flow.generationSources == nil)
        #expect(flow.savedReports[day] == (commitFails ? saved : nil))
        #expect(flow.body == (commitFails ? saved.markdown : ""))
    }

    @Test func changedClearScopeInvalidatesTheOldConfirmationAndWindowCloseReleasesCounts() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report)); flow.send(.open(.settings)); await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        flow.send(.requestSettingsPage(.contentManagement)); flow.send(.requestClearReports)
        let previous = try #require(flow.confirmation).id
        flow.send(.editBody("确认期间的新草稿", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        #expect(flow.confirmation?.id != previous)
        flow.send(.confirm(previous)); await flow.waitForStorage()
        #expect(flow.hasDraft)
        flow.send(.cancelConfirmation)
        flow.send(.requestCloseReport(session)); flow.send(.confirm(try #require(flow.confirmation).id))
        flow.send(.windowClosed(.report, session: session))
        #expect(flow.contentCounts.drafts == 0 && flow.contentCounts.snapshots == 0)
    }

    @Test func faultResetHasAnIndependentConfirmationAndReinitializesWithoutNetwork() async throws {
        let environment = ReportFlowTestEnvironment()
        await environment.storage.failLoads(.invalidData)
        let flow = environment.makeFlow()
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.contentManagement))
        #expect(!flow.isStorageReady)
        flow.send(.requestResetReportData)
        #expect(flow.confirmation?.windowKind == .settings)
        flow.send(.cancelConfirmation)
        #expect(flow.storageError == .invalidData)
        flow.send(.requestResetReportData)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.isStorageReady)
        #expect(flow.storageError == nil)
        #expect(flow.codexSourceStatus == .unchecked)
        #expect(flow.currentAIService == nil)
        #expect(flow.contentCounts == ReportContentCounts(saved: 0, drafts: 0, snapshots: 0))
        #expect(await environment.codex.checkCount == 0)
        #expect(await environment.codex.scanCount == 0)
        #expect(await environment.ai.requests.isEmpty)
    }

    @Test func clearListsAllTimeZonesAndMemoryCountsAndPreservesSettingsAndCredentials() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("retained-choice")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let today = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("保存正文", day: today, session: session, revision: flow.reportEditRevision))
        flow.send(.save); await flow.waitForStorage()
        flow.send(.editBody("草稿一", day: today, session: session, revision: flow.reportEditRevision))
        let other = try ReportDay(calendarDate: today.calendarDate, timeZoneIdentifier: "Asia/Shanghai")
        flow.send(.selectReportDay(other))
        flow.send(.editBody("跨时区草稿", day: other, session: session, revision: flow.reportEditRevision))
        let settings = try await environment.storage.load()
        #expect(flow.contentCounts == ReportContentCounts(saved: 1, drafts: 2, snapshots: 1))
        flow.send(.requestSettingsPage(.contentManagement))
        flow.send(.requestClearReports)
        let pending = try #require(flow.confirmation)
        #expect(pending.contentCounts == flow.contentCounts)
        #expect(Set(pending.draftDays) == [today, other])
        flow.send(.cancelConfirmation)
        #expect(flow.contentCounts.drafts == 2)
        flow.send(.requestClearReports)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.contentCounts == ReportContentCounts(saved: 0, drafts: 0, snapshots: 0))
        flow.send(.selectReportDay(today))
        #expect(flow.selectedSessionIDs.isEmpty)
        #expect(flow.sessionScan == nil)
        let loaded = try await environment.storage.load()
        #expect(loaded.generalSettings == settings.generalSettings)
        #expect(loaded.codexSource == settings.codexSource)
        #expect(loaded.aiServices == settings.aiServices)
    }

    @Test func failedDeletionKeepsContentAndSelectionButRejectsOldEdits() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareSessionFlow(environment, sessions: [syntheticCandidate("candidate")])
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        let day = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("原文", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save); await flow.waitForStorage()
        flow.send(.editBody("原草稿", day: day, session: session, revision: flow.reportEditRevision))
        let revision = flow.reportEditRevision
        await environment.storage.failSaves(true)
        flow.send(.requestDeleteReport(day)); flow.send(.confirm(try #require(flow.confirmation).id))
        await flow.waitForStorage()
        #expect(flow.body == "原草稿")
        #expect(flow.savedReports[day]?.markdown == "原文")
        #expect(flow.selectedSessionIDs == ["candidate"])
        #expect(flow.confirmedSnapshot != nil)
        #expect(flow.storageError == .writeFailed)
        flow.send(.editBody("旧提交", day: day, session: session, revision: revision))
        #expect(flow.body == "原草稿")
    }

    @Test func singleDeletionConfirmsCoexistingDraftAndCommitsBeforeClearingMemory() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report)); await flow.waitForStorage()
        let day = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("已保存 SYNTHETIC_DELETE_33", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save); await flow.waitForStorage()
        flow.send(.editBody("共存草稿 SYNTHETIC_DRAFT_33", day: day, session: session, revision: flow.reportEditRevision))
        let oldRevision = flow.reportEditRevision
        flow.send(.requestDeleteReport(day))
        let confirmation = try #require(flow.confirmation)
        #expect(confirmation.draftDays == [day])
        #expect(flow.savedReports[day] != nil)
        flow.send(.cancelConfirmation)
        #expect(flow.hasDraft)
        flow.send(.requestDeleteReport(day))
        await environment.storage.holdNextSave()
        flow.send(.confirm(try #require(flow.confirmation).id))
        await environment.storage.waitUntilSaveIsHeld()
        #expect(flow.savedReports[day] != nil)
        #expect(flow.hasDraft)
        flow.send(.editBody("排队旧编辑", day: day, session: session, revision: oldRevision))
        await environment.storage.releaseSave(); await flow.waitForStorage()
        #expect(flow.savedReports[day] == nil)
        #expect(!flow.hasDraft)
        flow.send(.editBody("迟到旧编辑", day: day, session: session, revision: oldRevision))
        #expect(!flow.hasDraft)
        #expect(try await environment.storage.load().reports.isEmpty)
    }
}
