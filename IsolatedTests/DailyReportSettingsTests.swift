import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportSettingsTests {
    @Test(arguments: ["Etc/GMT", "Etc/GMT+8", "Etc/GMT+12", "Etc/GMT-3", "Etc/GMT-14", "CET", "EET", "MET", "WET", "CST6CDT", "PST8PDT"])
    func validFixedIanaZonesCanBeSelectedSavedAndReopened(_ identifier: String) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = identifier
        let isSearchable = ReportTimeZone.searchableIdentifiers.contains(identifier)
        #expect(isSearchable)
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        #expect(flow.settingsValidationError == nil)
        #expect(flow.generalSettings == edited)
        #expect(flow.effectiveReportTimeZone == TimeZone(identifier: identifier))
        let reopened = environment.makeFlow()
        reopened.send(.open(.settings))
        await reopened.waitForStorage()
        #expect(reopened.generalSettings == edited)
    }

    @Test(arguments: ["GMT+0800", "GMT-8", "INVALID/IANA_24", "", "Asia/Shanghai "])
    func invalidFixedIanaNamesRemainUnchangedAndCannotBeSaved(_ identifier: String) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let original = flow.generalSettings
        var edited = original
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = identifier
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        #expect(flow.settingsValidationError == .invalidTimeZone)
        #expect(flow.generalSettings == original)
        #expect(flow.generalSettingsEdit == edited)
    }

    @Test(arguments: [false, true])
    func automaticTimeZoneChangeWaitsForReportCommitBeforeClearingOldDrafts(_ fails: Bool) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let day = flow.selectedDay
        let revision = flow.reportEditRevision
        flow.send(.editBody("显式保存的旧时区正文", day: day, session: session, revision: revision))
        flow.send(.moveDate(1))
        let otherDay = flow.selectedDay
        flow.send(.editBody("另一天未保存草稿", day: otherDay, session: session, revision: revision))
        flow.send(.selectReportDay(day))
        await environment.storage.failSaves(fails)
        await environment.storage.holdNextSave()
        flow.send(.save)
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Tokyo")!))
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Shanghai")!))
        #expect(flow.isSaving)
        #expect(flow.effectiveTimeZoneIdentifier == "Etc/UTC")
        #expect(flow.draftDays == [day, otherDay])
        #expect(environment.contextEffects.isEmpty)
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(!flow.isSaving)
        #expect(flow.effectiveTimeZoneIdentifier == "Asia/Shanghai")
        #expect(flow.draftDays.isEmpty)
        #expect(flow.savedReports[day]?.markdown == (fails ? nil : "显式保存的旧时区正文"))
        #expect(flow.notice?.contains(fails ? "2 份" : "1 份") == true)
        #expect(environment.contextEffects == [
            .cancelTimeZoneTasks("Etc/UTC", revision: revision + 1),
            .rescan(flow.selectedDay, revision: revision + 1)
        ])
        let snapshot = try await environment.storage.load()
        #expect(snapshot.reports == (fails ? [] : [try #require(flow.savedReports[day])]))
        flow.send(.selectReportDay(otherDay))
        flow.send(.editBody("迟到编辑不能恢复", day: otherDay, session: session, revision: revision))
        #expect(!flow.hasDraft)
    }

    @Test(arguments: [false, true], [false, true])
    func automaticTimeZoneChangeWaitsForSettingsCommitAndRetainsItsTargetDrafts(
        _ fails: Bool, _ fixesTimeZone: Bool
    ) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let reportSession = try #require(flow.openWindows[.report])
        let oldDay = flow.selectedDay
        flow.send(.editBody("提交前旧时区草稿", day: oldDay, session: reportSession, revision: flow.reportEditRevision))
        let targetDay = ReportDay(date: environment.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        flow.send(.selectReportDay(targetDay))
        flow.send(.editBody("提交后保留目标草稿", day: targetDay, session: reportSession, revision: flow.reportEditRevision))
        let original = flow.generalSettings
        var edited = original
        edited.outputLanguage = .english
        if fixesTimeZone {
            edited.timeZoneMode = .fixed
            edited.fixedTimeZoneIdentifier = "Asia/Shanghai"
        }
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        await environment.storage.failSaves(fails)
        await environment.storage.holdNextSave()
        flow.send(.saveGeneralSettings)
        if let confirmation = flow.confirmation { flow.send(.confirm(confirmation.id)) }
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Tokyo")!))
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Shanghai")!))
        #expect(flow.effectiveTimeZoneIdentifier == "Etc/UTC")
        #expect(flow.draftDays.contains(oldDay))
        #expect(environment.contextEffects.isEmpty)
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(flow.generalSettings == (fails ? original : edited))
        #expect(flow.generalSettingsEdit == edited)
        #expect(flow.effectiveTimeZoneIdentifier == "Asia/Shanghai")
        #expect(flow.draftDays == [targetDay])
        #expect(flow.body == "提交后保留目标草稿")
        #expect(environment.contextEffects.count == 2)
        #expect(flow.settingsStorageError == (fails ? .writeFailed : nil))
    }

    @Test func invalidSavedFixedTimeZoneRemainsUnchangedAndBlocksNewInputsUntilRepaired() async throws {
        let environment = ReportFlowTestEnvironment()
        var invalid = DailyReportGeneralSettings()
        invalid.timeZoneMode = .fixed
        invalid.fixedTimeZoneIdentifier = "INVALID/IANA_24"
        await environment.storage.setGeneralSettings(invalid)
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        #expect(flow.generalSettings == invalid)
        #expect(flow.effectiveTimeZoneIdentifier == nil)
        #expect(!flow.canUseReportTimeZone)
        let session = try #require(flow.openWindows[.report])
        flow.send(.editBody("不得隐式使用 Mac 时区", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        #expect(!flow.hasDraft)
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Tokyo")!))
        #expect(flow.effectiveTimeZoneIdentifier == nil)
        #expect(environment.contextEffects.isEmpty)
        flow.send(.requestSettingsPage(.general))
        flow.send(.saveGeneralSettings)
        #expect(flow.settingsValidationError == .invalidTimeZone)
        #expect(flow.generalSettings == invalid)
        var repaired = invalid
        repaired.fixedTimeZoneIdentifier = "Asia/Shanghai"
        flow.send(.editGeneralSettings(repaired, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        #expect(flow.canUseReportTimeZone)
        #expect(flow.effectiveTimeZoneIdentifier == "Asia/Shanghai")
        #expect(environment.contextEffects == [.rescan(flow.selectedDay, revision: flow.reportEditRevision)])
    }

    @Test func changingOnlyTheModeRetainsDraftsAndNonTimeZoneSettingsOnlyAffectNewGenerationValues() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let day = flow.selectedDay
        flow.send(.editBody("模式不改变时区", day: day, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        let runningGenerationValues = flow.generalSettings
        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = "Etc/UTC"
        edited.outputLanguage = .english
        edited.generationPreferences = "下一次才生效 PREFERENCES_NEXT_24"
        edited.historyLookbackDays = 0
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        #expect(flow.confirmation == nil)
        await flow.waitForStorage()
        #expect(flow.generalSettings == edited)
        #expect(runningGenerationValues.outputLanguage == .chinese)
        #expect(runningGenerationValues.generationPreferences.isEmpty)
        #expect(runningGenerationValues.historyLookbackDays == 1)
        #expect(flow.draftDays == [day])
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Tokyo")!))
        #expect(flow.effectiveTimeZoneIdentifier == "Etc/UTC")
        #expect(flow.draftDays == [day])
        #expect(environment.contextEffects.isEmpty)
    }

    @Test(arguments: [-1, 8])
    func invalidHistoryLookbackIsRejectedWithoutSavingOtherEdits(_ days: Int) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let original = flow.generalSettings
        var edited = original
        edited.outputLanguage = .english
        edited.historyLookbackDays = days
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        #expect(flow.settingsValidationError == .invalidLookback)
        #expect(flow.generalSettings == original)
        #expect(flow.generalSettingsEdit == edited)
    }

    @Test func confirmationKeepsItsIntentWhileDraftsAndAutomaticTimeZonesChange() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let reportSession = try #require(flow.openWindows[.report])
        flow.send(.editBody("原范围", day: flow.selectedDay, session: reportSession, revision: flow.reportEditRevision))
        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = "Asia/Shanghai"
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.saveGeneralSettings)
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.moveDate(1))
        #expect(flow.confirmation?.windowKind == .settings)
        flow.send(.editBody("增加的日期", day: flow.selectedDay, session: reportSession, revision: flow.reportEditRevision))
        #expect(flow.confirmation?.draftDays.count == 2)
        #expect(flow.confirmation?.id != obsolete)
        flow.send(.confirm(obsolete))
        #expect(!flow.isSaving)
        let beforeAutomaticChange = try #require(flow.confirmation?.id)
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Tokyo")!))
        #expect(flow.confirmation?.windowKind == .settings)
        #expect(flow.confirmation?.id != beforeAutomaticChange)
        #expect(flow.confirmation?.oldTimeZoneIdentifier == "Asia/Tokyo")
        #expect(flow.confirmation?.draftDays.isEmpty == true)
        flow.send(.confirm(beforeAutomaticChange))
        #expect(!flow.isSaving)
        #expect(flow.generalSettings.timeZoneMode == .followMac)
    }

    @Test func closingSettingsCanCancelDiscardOrSaveWithoutClosingTheReport() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let reportSession = try #require(flow.openWindows[.report])
        let settingsSession = try #require(flow.openWindows[.settings])
        let day = flow.selectedDay
        flow.send(.editBody("设置放弃仍保留日报草稿", day: day, session: reportSession, revision: flow.reportEditRevision))
        var edited = flow.generalSettingsEdit
        edited.outputLanguage = .english
        flow.send(.editGeneralSettings(edited, session: settingsSession))
        flow.send(.requestCloseSettings(settingsSession))
        #expect(flow.confirmation?.draftDays.isEmpty == true)
        flow.send(.cancelConfirmation)
        #expect(!environment.effects.contains(.closeSettings(session: settingsSession)))
        flow.send(.requestCloseSettings(settingsSession))
        flow.send(.discardSettingsAndContinue(try #require(flow.confirmation?.id)))
        #expect(environment.effects.last == .closeSettings(session: settingsSession))
        #expect(flow.generalSettings.outputLanguage == .chinese)
        #expect(flow.draftDays == [day])
        flow.send(.windowClosed(.settings, session: settingsSession))
        flow.send(.open(.settings))
        let reopened = try #require(flow.openWindows[.settings])
        #expect(reopened != settingsSession)
        flow.send(.requestSettingsPage(.general))
        flow.send(.editGeneralSettings(edited, session: reopened))
        flow.send(.requestCloseSettings(settingsSession))
        #expect(flow.confirmation == nil)
        await environment.storage.failSaves(true)
        flow.send(.requestCloseSettings(reopened))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.openWindows[.settings] == reopened)
        #expect(flow.settingsPage == .general)
        #expect(flow.hasGeneralSettingsEdits)
        await environment.storage.failSaves(false)
        flow.send(.requestCloseSettings(reopened))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(environment.effects.last == .closeSettings(session: reopened))
        #expect(flow.generalSettings.outputLanguage == .english)
        #expect(flow.openWindows[.report] == reportSession)
        #expect(flow.draftDays == [day])
    }

    @Test(arguments: [false, true])
    func quitCombinesUnsavedSettingsAndAllReportDraftsWithCancellationAsTheDefault(_ saveSettings: Bool) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let day = flow.selectedDay
        flow.send(.editBody("退出保护", day: day, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        var edited = flow.generalSettingsEdit
        edited.outputLanguage = .english
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        #expect(!flow.canTerminate)
        flow.send(.quit)
        #expect(flow.confirmation?.windowKind == .settings)
        #expect(flow.confirmation?.draftDays == [day])
        flow.send(.cancelConfirmation)
        #expect(flow.hasGeneralSettingsEdits)
        #expect(flow.hasDraft)
        #expect(!environment.effects.contains(.quit))
        flow.send(.quit)
        let id = try #require(flow.confirmation?.id)
        if saveSettings { flow.send(.confirm(id)) } else { flow.send(.discardSettingsAndContinue(id)) }
        await flow.waitForStorage()
        #expect(environment.effects.last == .quit)
        #expect(flow.draftDays.isEmpty)
        #expect(flow.generalSettings.outputLanguage == (saveSettings ? .english : .chinese))
    }

    @Test(arguments: [ReportSettingsPage.dataSource, .aiServices, .intelligence, .proximityUnlock])
    func leavingGeneralSettingsCombinesSaveAndDraftImpactAndFailureKeepsThePage(_ destination: ReportSettingsPage) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let day = flow.selectedDay
        flow.send(.editBody("离页影响", day: day, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = "Asia/Shanghai"
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        flow.send(.requestSettingsPage(destination))
        #expect(flow.settingsPage == .general)
        #expect(flow.confirmation?.windowKind == .settings)
        #expect(flow.confirmation?.draftDays == [day])
        flow.send(.cancelConfirmation)
        #expect(flow.generalSettingsEdit == edited)
        #expect(flow.hasDraft)

        await environment.storage.failSaves(true)
        flow.send(.requestSettingsPage(destination))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.settingsPage == .general)
        #expect(flow.hasGeneralSettingsEdits)
        #expect(flow.draftDays == [day])
        await environment.storage.failSaves(false)
        flow.send(.requestSettingsPage(destination))
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.settingsPage == destination)
        #expect(!flow.hasGeneralSettingsEdits)
        #expect(flow.draftDays.isEmpty)
        #expect(flow.confirmation == nil)
    }

    @Test func automaticMacTimeZoneChangeClearsOldDatesAndRejectsLateEditsWithoutConfirmation() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let first = flow.selectedDay
        flow.send(.editBody("第一份自动影响", day: first, session: session, revision: flow.reportEditRevision))
        flow.send(.moveDate(1))
        flow.send(.editBody("第二份自动影响", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        let oldRevision = flow.reportEditRevision
        let target = ReportDay(date: environment.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        flow.send(.selectReportDay(target))
        flow.send(.editBody("自动切换保留目标", day: target, session: session, revision: flow.reportEditRevision))
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Shanghai")!))
        #expect(flow.effectiveTimeZoneIdentifier == "Asia/Shanghai")
        #expect(flow.draftDays == [target])
        #expect(flow.confirmation == nil)
        #expect(flow.notice?.contains("2 份") == true)
        #expect(environment.contextEffects == [
            .cancelTimeZoneTasks("Etc/UTC", revision: oldRevision + 1),
            .rescan(target, revision: oldRevision + 1)
        ])
        flow.send(.systemTimeZoneChanged(TimeZone(identifier: "Asia/Shanghai")!))
        #expect(environment.contextEffects.count == 2)
        flow.send(.selectReportDay(first))
        flow.send(.editBody("过期编辑不能复活", day: first, session: session, revision: oldRevision))
        #expect(!flow.hasDraft)
    }

    @Test func manualTimeZoneChangeCommitsBeforeDiscardingAllOldDatesAndKeepsTargetDrafts() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let reportSession = try #require(flow.openWindows[.report])
        let settingsSession = try #require(flow.openWindows[.settings])
        let oldDay = flow.selectedDay
        flow.send(.editBody("已保存 OLD_REPORT_24", day: oldDay, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.save)
        await flow.waitForStorage()
        let saved = flow.savedReports
        flow.send(.editBody("旧时区第一份", day: oldDay, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.moveDate(1))
        let secondOldDay = flow.selectedDay
        flow.send(.editBody("旧时区第二份", day: secondOldDay, session: reportSession, revision: flow.reportEditRevision))
        let targetDay = ReportDay(date: environment.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        flow.send(.selectReportDay(targetDay))
        flow.send(.editBody("目标时区应保留", day: targetDay, session: reportSession, revision: flow.reportEditRevision))

        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = "Asia/Shanghai"
        edited.outputLanguage = .english
        edited.generationPreferences = "事务偏好 PREFERENCES_24"
        edited.historyLookbackDays = 0
        flow.send(.editGeneralSettings(edited, session: settingsSession))
        flow.send(.saveGeneralSettings)
        #expect(flow.confirmation?.draftDays == [oldDay, secondOldDay])
        #expect(flow.effectiveTimeZoneIdentifier == "Etc/UTC")
        flow.send(.cancelConfirmation)
        #expect(flow.generalSettings != edited)
        #expect(flow.draftDays.count == 3)

        flow.send(.saveGeneralSettings)
        await environment.storage.holdNextSave()
        await environment.storage.failSaves(true)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await environment.storage.waitUntilSaveIsHeld()
        flow.send(.editBody("不得在提交期间改变", day: targetDay, session: reportSession, revision: flow.reportEditRevision))
        flow.send(.requestCloseReport(reportSession))
        flow.send(.quit)
        #expect(flow.isSaving)
        #expect(flow.body == "目标时区应保留")
        #expect(flow.draftDays.count == 3)
        await environment.storage.releaseSave()
        await flow.waitForStorage()
        #expect(flow.settingsStorageError == .writeFailed)
        #expect(flow.effectiveTimeZoneIdentifier == "Etc/UTC")
        #expect(flow.generalSettingsEdit == edited)
        #expect(flow.draftDays.count == 3)
        #expect(flow.savedReports == saved)

        await environment.storage.failSaves(false)
        flow.send(.saveGeneralSettings)
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(flow.generalSettings == edited)
        #expect(flow.effectiveTimeZoneIdentifier == "Asia/Shanghai")
        #expect(flow.draftDays == [targetDay])
        #expect(flow.savedReports == saved)
        #expect(flow.body == "目标时区应保留")
    }

    @Test func generalSettingsCommitTogetherAndRevertToSavedValues() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        let session = try #require(flow.openWindows[.settings])
        #expect(flow.generalSettings.historyLookbackDays == 1)
        var edited = flow.generalSettingsEdit
        edited.outputLanguage = .english
        edited.generationPreferences = "  合成偏好 PREFERENCES_24 👩🏽‍💻\n"
        edited.historyLookbackDays = 7
        flow.send(.editGeneralSettings(edited, session: session))
        #expect(flow.generalSettings.outputLanguage == .chinese)
        #expect(flow.hasGeneralSettingsEdits)
        flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        #expect(flow.generalSettings == edited)
        #expect(!flow.hasGeneralSettingsEdits)

        var unsaved = edited
        unsaved.historyLookbackDays = 0
        flow.send(.editGeneralSettings(unsaved, session: session))
        flow.send(.revertGeneralSettings)
        #expect(flow.generalSettingsEdit == edited)
        let reopened = environment.makeFlow()
        reopened.send(.open(.settings))
        await reopened.waitForStorage()
        #expect(reopened.generalSettings == edited)
    }
}
