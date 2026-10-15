import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportContentTests {
    @Test func lateSheetDismissalCannotCancelAnAlreadyConfirmedQuit() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("确认放弃", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(CGSize(width: 1200, height: 800), session: session))
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.quit)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        flow.send(.cancelConfirmation)
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(environment.effects.last == .quit)
    }

    @Test func returningToEditingCancelsAnEarlierQuitWaitingForSize() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let day = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("已保存基线", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(CGSize(width: 1200, height: 800), session: session))
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.quit)
        flow.send(.editBody("有效修改", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.quit)
        #expect(flow.confirmation?.draftDays == [day])
        flow.send(.cancelConfirmation)
        flow.send(.editBody("已保存基线", day: day, session: session, revision: flow.reportEditRevision))
        #expect(!flow.hasDraft)
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(!environment.effects.contains(.quit))
        #expect(flow.confirmation == nil)
    }

    @Test func aNewDraftWhileWaitingForSizeRequiresQuitConfirmation() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(CGSize(width: 1200, height: 800), session: session))
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.quit)
        flow.send(.editBody("等待期间的新草稿", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(!environment.effects.contains(.quit))
        #expect(flow.confirmation?.draftDays == [flow.selectedDay])
        flow.send(.cancelConfirmation)
        #expect(flow.hasDraft)
    }

    @Test(arguments: [false, true])
    func quittingWaitsForTheFinalSizeWriteBeforeTerminating(_ hasDraft: Bool) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        if hasDraft { flow.send(.editBody("需确认放弃", day: flow.selectedDay, session: session, revision: flow.reportEditRevision)) }
        let finalSize = CGSize(width: 1200, height: 800)
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(finalSize, session: session))
        await environment.storage.waitUntilSaveIsHeld()
        #expect(!flow.canTerminate)
        flow.send(.quit)
        if hasDraft { flow.send(.confirm(try #require(flow.confirmation?.id))) }
        #expect(!environment.effects.contains(.quit))
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(flow.canTerminate)
        #expect(environment.effects.last == .quit)
        let reopened = environment.makeFlow()
        reopened.send(.open(.report))
        await reopened.waitForStorage()
        #expect(reopened.reportWindowSize == finalSize)
    }

    @Test func returningToThePreviousSizeDuringAWritePersistsTheFinalSize() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let initial = CGSize(width: 1100, height: 760)
        flow.send(.normalReportSizeChanged(initial, session: session))
        await flow.waitForStorage()
        await environment.storage.holdNextSave()
        flow.send(.normalReportSizeChanged(CGSize(width: 1200, height: 800), session: session))
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.normalReportSizeChanged(initial, session: session))
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        let reopened = environment.makeFlow()
        reopened.send(.open(.report))
        await reopened.waitForStorage()
        #expect(reopened.reportWindowSize == initial)
    }

    @Test func unavailableStorageBlocksDraftsAndCommitFreezesTheConfirmedBody() async throws {
        let blocked = ReportFlowTestEnvironment()
        await blocked.storage.failLoads(.occupied)
        let blockedFlow = blocked.makeFlow()
        blockedFlow.send(.open(.report))
        await blockedFlow.waitForStorage()
        blockedFlow.send(.editBody("不得创建", day: blockedFlow.selectedDay, session: try #require(blockedFlow.openWindows[.report]), revision: blockedFlow.reportEditRevision))
        #expect(!blockedFlow.isStorageReady)
        #expect(blockedFlow.storageError == .occupied)
        #expect(!blockedFlow.hasDraft)

        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("明确保存的版本", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        await environment.storage.holdNextSave()
        flow.send(.save)
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.editBody("提交期间不能替换", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.requestCloseReport(session))
        flow.send(.quit)
        #expect(flow.isSaving)
        #expect(flow.body == "明确保存的版本")
        #expect(!environment.effects.contains(.closeReport(session: session)))
        #expect(!environment.effects.contains(.quit))
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(flow.savedReports[flow.selectedDay]?.markdown == "明确保存的版本")
        #expect(!flow.hasDraft)
    }

    @Test func normalSizeAndSavedReportsReturnWhenTheWindowReopens() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let day = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("已保存的正文", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        flow.send(.normalReportSizeChanged(CGSize(width: 1234, height: 789), session: session))
        await flow.waitForStorage()
        flow.send(.save)
        #expect(flow.confirmation != nil)
        flow.send(.windowClosed(.report, session: session))
        #expect(flow.confirmation == nil)
        flow.send(.open(.report))
        #expect(environment.effects.last == .restoreReportSize(
            CGSize(width: 1234, height: 789), session: try #require(flow.openWindows[.report])
        ))
        let reopened = environment.makeFlow()
        reopened.send(.open(.report))
        await reopened.waitForStorage()
        #expect(reopened.body == "已保存的正文")
        #expect(!reopened.hasDraft)
        #expect(reopened.reportWindowSize == CGSize(width: 1234, height: 789))
        #expect(reopened.historyDays == [day])
        #expect(AppWindowConfiguration.report.restoredContentSize(
            stored: CGSize(width: 2000, height: 1500), visibleContentSize: CGSize(width: 1400, height: 900)
        ) == CGSize(width: 1400, height: 900))
        #expect(AppWindowConfiguration.report.restoredContentSize(
            stored: CGSize(width: 500, height: 300), visibleContentSize: CGSize(width: 1400, height: 900)
        ) == CGSize(width: 900, height: 620))
    }

    @Test func closingProtectsAllDatesAndTimeZonesAndInvalidatesOldEdits() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let first = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("第一份", day: first, session: session, revision: flow.reportEditRevision))
        let other = ReportDay(date: environment.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        flow.send(.selectReportDay(other))
        flow.send(.editBody("第二份", day: other, session: session, revision: flow.reportEditRevision))
        flow.send(.requestCloseReport(session))
        let obsolete = try #require(flow.confirmation?.id)
        #expect(Set(flow.confirmation?.draftDays ?? []) == [first, other])
        #expect(!environment.effects.contains(.closeReport(session: session)))
        flow.send(.editBody("第二份修订", day: other, session: session, revision: flow.reportEditRevision))
        flow.send(.confirm(obsolete))
        #expect(!environment.effects.contains(.closeReport(session: session)))
        flow.send(.cancelConfirmation)
        #expect(flow.draftDays.count == 2)

        flow.send(.requestDiscardDraft)
        flow.send(.cancelConfirmation)
        #expect(flow.hasDraft)
        flow.send(.requestDiscardDraft)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        #expect(!flow.hasDraft)
        #expect(flow.draftDays == [first])
        flow.send(.quit)
        #expect(flow.confirmation?.draftDays == [first])
        flow.send(.cancelConfirmation)
        flow.send(.requestCloseReport(session))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        #expect(environment.effects.last == .closeReport(session: session))
        flow.send(.windowClosed(.report, session: session))
        #expect(flow.draftDays.isEmpty)
        flow.send(.open(.report))
        flow.send(.editBody("迟到的旧编辑", day: first, session: session, revision: flow.reportEditRevision))
        #expect(flow.body.isEmpty)
        #expect(!flow.hasDraft)
    }

    @Test func overwriteConfirmationRejectsChangedBodyAndFailureKeepsOriginalAndDraft() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let day = flow.selectedDay
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("原文\n", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        let original = try #require(flow.savedReports[day])

        flow.send(.editBody("原文 \n", day: day, session: session, revision: flow.reportEditRevision))
        #expect(flow.hasDraft)
        flow.send(.editBody("原文\n", day: day, session: session, revision: flow.reportEditRevision))
        #expect(!flow.hasDraft)
        flow.send(.editBody("修改一\n", day: day, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.editBody("修改二\n", day: day, session: session, revision: flow.reportEditRevision))
        let refreshed = try #require(flow.confirmation)
        #expect(refreshed.id != obsolete)
        #expect(refreshed.markdown == "修改二\n")
        flow.send(.confirm(obsolete))
        await flow.waitForStorage()
        #expect(flow.savedReports[day] == original)

        await environment.storage.failSaves(true)
        flow.send(.confirm(refreshed.id))
        await flow.waitForStorage()
        #expect(flow.savedReports[day] == original)
        #expect(flow.hasDraft)
        #expect(flow.body == "修改二\n")
        #expect(flow.storageError == .writeFailed)
        await environment.storage.failSaves(false)
        flow.send(.save)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.savedReports[day]?.markdown == "修改二\n")
        #expect(!flow.hasDraft)

        environment.now = Date(timeIntervalSince1970: 3_000)
        let editTime = flow.savedReports[day]?.lastEditedAt
        flow.send(.save)
        #expect(flow.confirmation?.previousMarkdown == flow.confirmation?.markdown)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.savedReports[day]?.savedAt == environment.now)
        #expect(flow.savedReports[day]?.lastEditedAt == editTime)
    }

    @Test func explicitFirstSaveAllowsEmptyAndCopiesRawMarkdown() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let emptyDay = flow.selectedDay
        flow.send(.save)
        await flow.waitForStorage()
        #expect(flow.savedReports[emptyDay]?.markdown == "")
        #expect(flow.savedReports[emptyDay]?.lastEditedAt == nil)
        #expect(flow.confirmation == nil)

        flow.send(.moveDate(1))
        let raw = "# 任意标题\n\n 合成手写秘密 RAW_SECRET_23\u{0}👩🏽‍💻  \n"
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody(raw, day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.copyMarkdown)
        #expect(environment.copies == [raw])
        environment.now = Date(timeIntervalSince1970: 2_000)
        flow.send(.save)
        await flow.waitForStorage()
        #expect(flow.savedReports[flow.selectedDay]?.markdown.utf8.elementsEqual(raw.utf8) == true)
        #expect(flow.savedReports[flow.selectedDay]?.savedAt == environment.now)
        #expect(flow.savedReports[flow.selectedDay]?.lastEditedAt == Date(timeIntervalSince1970: 1_000))
        #expect(!flow.hasDraft)
    }

    @Test func handwritingRemainsADraftAfterErasingAndAcrossDateNavigation() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let today = flow.selectedDay
        let session = try #require(flow.openWindows[.report])

        flow.send(.editBody("  手写 👩🏽‍💻\n", day: today, session: session, revision: flow.reportEditRevision))
        #expect(flow.body == "  手写 👩🏽‍💻\n")
        #expect(flow.hasDraft)
        flow.send(.moveDate(1))
        #expect(flow.body.isEmpty)
        #expect(!flow.hasDraft)
        flow.send(.selectReportDay(today))
        flow.send(.editBody("", day: today, session: session, revision: flow.reportEditRevision))
        #expect(flow.hasDraft)
        #expect(flow.draftDays == [today])
        flow.send(.hide)
        flow.send(.minimizeReport)
        #expect(flow.hasDraft)
    }
}

@MainActor
final class ReportFlowTestEnvironment {
    let storage = ControlledReportStorage()
    let codex = ControlledCodexSource()
    let credentials = ControlledCredentials()
    let ai = ControlledAIService()
    var now = Date(timeIntervalSince1970: 1_000)
    var effects: [AppWindowEffect] = []
    var copies: [String] = []
    var contextEffects: [ReportContextEffect] = []
    var codexEvents: [CodexCheckEvent] = []
    var scanEvents: [CodexScanEvent] = []
    var aiStorageEvents: [AIServiceStorageEvent] = []
    var aiValidationEvents: [AIValidationEvent] = []
    var redact: @Sendable (String) throws -> String = { $0 }
    var tokenizer: any ReportTokenCounting = OfflineReportTokenizer()

    func makeFlow(timeZone: TimeZone = TimeZone(identifier: "Etc/UTC")!) -> DailyReportFlow {
        DailyReportFlow(
            storage: storage,
            aiCredentials: credentials,
            aiAccess: self.ai, reportTokenizer: self.tokenizer, codexSourceAccess: codex,
            now: { self.now },
            timeZone: timeZone,
            performWindowEffect: { self.effects.append($0) },
            performContextEffect: { self.contextEffects.append($0) },
            recordWindowMode: { _ in },
            recordCodexCheck: { self.codexEvents.append($0) },
            recordSessionScan: { self.scanEvents.append($0) },
            recordAIStorage: { self.aiStorageEvents.append($0) },
            recordAIValidation: { self.aiValidationEvents.append($0) }, recordGeneration: { _ in }, redactCredentials: self.redact,
            copyText: { self.copies.append($0) }
        )
    }
}

actor ControlledReportStorage: DailyReportStorage {
    private var snapshot = ReportStorageSnapshot(reports: [], windowSize: nil, generalSettings: DailyReportGeneralSettings(), codexSource: CodexDataSourceSettings(), aiServices: AIServiceSettings())
    private var saveFailure = false
    private var loadFailure: ReportStorageError?
    private var holdsNextSave = false
    private var heldSave: CheckedContinuation<Void, Never>?
    private var saveObserver: CheckedContinuation<Void, Never>?

    func load() async throws -> ReportStorageSnapshot {
        if let loadFailure { throw loadFailure }
        return snapshot
    }

    func save(_ report: SavedDailyReport) async throws {
        await waitForSaveIfHeld()
        if saveFailure { throw ReportStorageError.writeFailed }
        snapshot.reports.removeAll { $0.day == report.day }
        snapshot.reports.append(report)
    }

    func saveWindowSize(_ size: CGSize) async throws {
        await waitForSaveIfHeld()
        snapshot.windowSize = size
    }

    func saveGeneralSettings(_ settings: DailyReportGeneralSettings) async throws {
        await waitForSaveIfHeld()
        if saveFailure { throw ReportStorageError.writeFailed }
        snapshot.generalSettings = settings
    }

    func saveCodexSource(_ settings: CodexDataSourceSettings) async throws {
        await waitForSaveIfHeld()
        if saveFailure { throw ReportStorageError.writeFailed }
        snapshot.codexSource = settings
    }

    func saveCodexDiagnostic(identity: CodexSourceIdentity, checkedAt: Date, version: CodexVersion?) async throws {
        if saveFailure { throw ReportStorageError.writeFailed }
        guard snapshot.codexSource.identity == identity else { return }
        snapshot.codexSource.lastSuccessfulCheck = checkedAt
        snapshot.codexSource.version = version
    }

    func saveAIService(_ service: SavedAIService) async throws {
        await waitForSaveIfHeld()
        if saveFailure { throw ReportStorageError.writeFailed }
        snapshot.aiServices.configurations[service.configuration.service] = service
    }
    func saveCurrentAIService(_ service: AIServiceType) async throws {
        await waitForSaveIfHeld()
        if saveFailure { throw ReportStorageError.writeFailed }
        snapshot.aiServices.current = service
    }
    func saveAIValidation(_ proof: AIServiceValidation, matching baseline: AIValidationBaseline) async throws -> Bool {
        await waitForSaveIfHeld()
        try Task.checkCancellation()
        if saveFailure { throw ReportStorageError.writeFailed }
        guard var saved = snapshot.aiServices.configurations[baseline.service], saved.requestBaseline == baseline else { return false }
        saved.validation = proof
        snapshot.aiServices.configurations[baseline.service] = saved
        return true
    }
    func setAISettings(_ settings: AIServiceSettings) { snapshot.aiServices = settings }

    private func waitForSaveIfHeld() async {
        if holdsNextSave {
            holdsNextSave = false
            await withCheckedContinuation { continuation in
                heldSave = continuation
                saveObserver?.resume()
                saveObserver = nil
            }
        }
    }
    func failSaves(_ value: Bool) { saveFailure = value }
    func setGeneralSettings(_ value: DailyReportGeneralSettings) { snapshot.generalSettings = value }
    func failLoads(_ error: ReportStorageError) { loadFailure = error }
    func holdNextSave() { holdsNextSave = true }
    func waitUntilSaveIsHeld() async {
        if heldSave == nil { await withCheckedContinuation { saveObserver = $0 } }
    }
    func releaseSave() { heldSave?.resume(); heldSave = nil }
}
