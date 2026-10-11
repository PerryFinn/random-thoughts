import Foundation
import Observation

@MainActor
@Observable
final class DailyReportFlow {
    enum Action: Sendable {
        case launch(AppLaunchReason)
        case open(AppWindowKind)
        case reactivate
        case windowClosed(AppWindowKind, session: UUID)
        case hide
        case minimizeReport
        case closeKeyWindow
        case quit
        case systemSleep
        case systemWake
        case selectDate(Date)
        case moveDate(Int)
        case toggleHistory
        case selectReportDay(ReportDay)
        case editBody(String, day: ReportDay, session: UUID, revision: UInt64)
        case save
        case copyMarkdown
        case confirm(UUID)
        case cancelConfirmation
        case requestDiscardDraft
        case requestCloseReport(UUID)
        case setPreview(Bool)
        case normalReportSizeChanged(CGSize, session: UUID)
        case requestSettingsPage(ReportSettingsPage)
        case editGeneralSettings(DailyReportGeneralSettings, session: UUID)
        case saveGeneralSettings
        case revertGeneralSettings
        case systemTimeZoneChanged(TimeZone)
        case requestCloseSettings(UUID)
        case discardSettingsAndContinue(UUID)
    }

    private(set) var openWindows: [AppWindowKind: UUID] = [:]
    private(set) var selectedDay: ReportDay
    private(set) var isHistoryVisible = true
    private(set) var isStorageReady = false
    private(set) var savedReports: [ReportDay: SavedDailyReport] = [:]
    private(set) var confirmation: ReportConfirmation?
    private(set) var isSaving = false
    private(set) var storageError: ReportStorageError?
    private(set) var notice: String?
    private(set) var isPreview = false
    private(set) var reportWindowSize: CGSize?
    private(set) var generalSettings = DailyReportGeneralSettings()
    private(set) var generalSettingsEdit = DailyReportGeneralSettings()
    private(set) var settingsPage: ReportSettingsPage = .intelligence
    private(set) var settingsValidationError: ReportSettingsValidationError?
    private(set) var settingsStorageError: ReportStorageError?
    private(set) var settingsNotice: String?
    private(set) var reportEditRevision: UInt64 = 0
    private var macTimeZone: TimeZone
    private var pendingMacTimeZone: TimeZone?
    private var drafts: [ReportDay: Draft] = [:]
    private var pendingSizeWrites = 0
    private var isLoadingStorage = false

    var reportTimeZone: TimeZone { selectedDay.timeZone }
    var hasGeneralSettingsEdits: Bool { generalSettingsEdit != generalSettings }
    var effectiveReportTimeZone: TimeZone? { generalSettings.effectiveTimeZone(macTimeZone: macTimeZone) }
    var effectiveTimeZoneIdentifier: String? { effectiveReportTimeZone.map(Self.timeZoneIdentifier) }
    var canUseReportTimeZone: Bool { isStorageReady && effectiveReportTimeZone != nil }
    var canEditSelectedReport: Bool { canUseReportTimeZone || savedReports[selectedDay] != nil || hasDraft }
    var editedTimeZoneIdentifier: String? {
        generalSettingsEdit.effectiveTimeZone(macTimeZone: macTimeZone).map(Self.timeZoneIdentifier)
    }
    var settingsDraftImpact: [ReportDay] {
        guard let old = effectiveTimeZoneIdentifier, let new = editedTimeZoneIdentifier, old != new else { return [] }
        return draftDays.filter { $0.timeZoneIdentifier == old }
    }
    var selectedDate: Date { selectedDay.start }
    var body: String { drafts[selectedDay]?.markdown ?? savedReports[selectedDay]?.markdown ?? "" }
    var hasDraft: Bool { drafts[selectedDay] != nil }
    var draftDays: [ReportDay] {
        drafts.keys.sorted { ($0.calendarDate, $0.timeZoneIdentifier) < ($1.calendarDate, $1.timeZoneIdentifier) }
    }
    var canTerminate: Bool { !isSaving && pendingSizeWrites == 0 && drafts.isEmpty && !hasGeneralSettingsEdits }
    var historyDays: [ReportDay] {
        Set(savedReports.keys).union(drafts.keys).sorted {
            ($0.calendarDate, $0.timeZoneIdentifier) > ($1.calendarDate, $1.timeZoneIdentifier)
        }
    }

    private struct Draft {
        var markdown: String
        let baseline: String
        let wasSaved: Bool
        var editedAt: Date
    }

    var windowMode: AppWindowMode {
        openWindows.isEmpty ? .menuBar : .foreground
    }

    @ObservationIgnored private let performWindowEffect: (AppWindowEffect) -> Void
    @ObservationIgnored private let performContextEffect: (ReportContextEffect) -> Void
    @ObservationIgnored private let recordWindowMode: (AppWindowMode) -> Void
    @ObservationIgnored private var lastAppliedMode: AppWindowMode?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let storage: any DailyReportStorage
    @ObservationIgnored private let copyMarkdown: (String) -> Void
    @ObservationIgnored private var storageTask: Task<Void, Never>?
    @ObservationIgnored private var quitTask: Task<Void, Never>?

    init(
        storage: any DailyReportStorage,
        now: @escaping () -> Date,
        timeZone: TimeZone,
        performWindowEffect: @escaping (AppWindowEffect) -> Void,
        performContextEffect: @escaping (ReportContextEffect) -> Void,
        recordWindowMode: @escaping (AppWindowMode) -> Void,
        copyMarkdown: @escaping (String) -> Void
    ) {
        self.storage = storage
        self.now = now
        macTimeZone = timeZone
        selectedDay = ReportDay(date: now(), timeZone: timeZone)
        self.performWindowEffect = performWindowEffect
        self.performContextEffect = performContextEffect
        self.recordWindowMode = recordWindowMode
        self.copyMarkdown = copyMarkdown
    }

    func waitForStorage() async {
        await storageTask?.value
        await quitTask?.value
    }

    func send(_ action: Action) {
        switch action {
        case .launch(.user):
            open(.report)
        case .launch(.login):
            applyMode()
        case .open(let kind):
            open(kind)
        case .reactivate:
            open(.report)
        case .windowClosed(let kind, let session):
            guard !isSaving, openWindows[kind] == session else { return }
            openWindows.removeValue(forKey: kind)
            if kind == .report {
                drafts.removeAll()
                if confirmation?.windowKind == .report { confirmation = nil }
            } else {
                generalSettingsEdit = generalSettings
                if confirmation?.windowKind == .settings { confirmation = nil }
            }
            if lastAppliedMode != windowMode {
                applyMode()
            }
        case .hide:
            performWindowEffect(.hide)
        case .minimizeReport:
            guard openWindows[.report] != nil else { return }
            performWindowEffect(.minimizeReport)
        case .closeKeyWindow:
            performWindowEffect(.closeKeyWindow)
        case .quit:
            guard !isSaving else { return }
            if hasGeneralSettingsEdits {
                setConfirmation(.settings(.quit))
                if let session = openWindows[.settings] { performWindowEffect(.present(.settings, session: session)) }
            } else if drafts.isEmpty {
                quitAfterPendingSizeWrites()
            } else {
                setConfirmation(.quit)
                if let session = openWindows[.report] {
                    performWindowEffect(.present(.report, session: session))
                }
            }
        case .systemSleep, .systemWake:
            applyMode()
        case .selectDate(let date):
            guard !isSaving else { return }
            selectedDay = ReportDay(date: date, timeZone: reportTimeZone)
            if confirmation?.windowKind == .report { confirmation = nil }
        case .moveDate(let offset):
            guard !isSaving else { return }
            if let date = selectedDay.calendar.date(byAdding: .day, value: offset, to: selectedDate) {
                selectedDay = ReportDay(date: date, timeZone: reportTimeZone)
                if confirmation?.windowKind == .report { confirmation = nil }
            }
        case .toggleHistory:
            isHistoryVisible.toggle()
        case .selectReportDay(let day):
            guard !isSaving else { return }
            selectedDay = day
            if confirmation?.windowKind == .report { confirmation = nil }
        case .editBody(let markdown, let day, let session, let revision):
            guard isStorageReady, canEditSelectedReport, !isSaving, openWindows[.report] == session, day == selectedDay,
                  revision == reportEditRevision,
                  !body.utf8.elementsEqual(markdown.utf8) else { return }
            var draft = drafts[day] ?? Draft(
                markdown: body, baseline: body, wasSaved: savedReports[day] != nil, editedAt: now()
            )
            draft.markdown = markdown
            draft.editedAt = now()
            if draft.wasSaved, markdown.utf8.elementsEqual(draft.baseline.utf8) {
                drafts.removeValue(forKey: day)
            } else {
                drafts[day] = draft
            }
            if let kind = confirmation?.kind { setConfirmation(kind) }
        case .copyMarkdown:
            copyMarkdown(body)
            notice = "已复制 Markdown"
        case .save:
            guard isStorageReady, canEditSelectedReport, !isSaving, openWindows[.report] != nil else { return }
            if let saved = savedReports[selectedDay] {
                setConfirmation(.overwrite(saved.day))
            } else {
                saveCurrentReport()
            }
        case .confirm(let id):
            guard let pending = confirmation, pending.id == id, !isSaving else { return }
            confirmation = nil
            switch pending.kind {
            case .overwrite(let day):
                guard day == selectedDay, pending.markdown?.utf8.elementsEqual(body.utf8) == true else { return }
                saveCurrentReport()
            case .discard(let day):
                drafts.removeValue(forKey: day)
            case .close(let session):
                guard openWindows[.report] == session else { return }
                drafts.removeAll()
                performWindowEffect(.closeReport(session: session))
            case .quit:
                drafts.removeAll()
                quitAfterPendingSizeWrites()
            case .settings(let continuation):
                guard openWindows[.settings] != nil, pending.settings == generalSettingsEdit else { return }
                settingsValidationError = generalSettingsEdit.validationError
                guard settingsValidationError == nil else { return }
                saveGeneralSettings(continuation: continuation)
            }
        case .cancelConfirmation:
            guard confirmation != nil else { return }
            confirmation = nil
            quitTask?.cancel()
            quitTask = nil
        case .requestDiscardDraft:
            guard !isSaving, hasDraft else { return }
            setConfirmation(.discard(selectedDay))
        case .requestCloseReport(let session):
            guard !isSaving, openWindows[.report] == session else { return }
            if drafts.isEmpty {
                performWindowEffect(.closeReport(session: session))
            } else {
                setConfirmation(.close(session))
            }
        case .setPreview(let value):
            isPreview = value
        case .normalReportSizeChanged(let size, let session):
            guard isStorageReady, openWindows[.report] == session, size != reportWindowSize else { return }
            reportWindowSize = size
            pendingSizeWrites += 1
            let previous = storageTask
            storageTask = Task {
                await previous?.value
                defer { pendingSizeWrites -= 1 }
                do {
                    try await storage.saveWindowSize(size)
                } catch {
                    if openWindows[.report] == session { storageError = error as? ReportStorageError ?? .writeFailed }
                }
            }
        case .requestSettingsPage(let page):
            guard !isSaving, openWindows[.settings] != nil, page != settingsPage else { return }
            if settingsPage == .general, hasGeneralSettingsEdits {
                setConfirmation(.settings(.page(page)))
            } else {
                settingsPage = page
            }
        case .editGeneralSettings(let settings, let session):
            guard isStorageReady, !isSaving, settingsPage == .general,
                  openWindows[.settings] == session else { return }
            generalSettingsEdit = settings
            settingsValidationError = nil
            settingsNotice = nil
            if let kind = confirmation?.kind { setConfirmation(kind) }
        case .saveGeneralSettings:
            guard isStorageReady, !isSaving, openWindows[.settings] != nil else { return }
            settingsValidationError = generalSettingsEdit.validationError
            guard settingsValidationError == nil else { return }
            if settingsDraftImpact.isEmpty {
                saveGeneralSettings(continuation: .stay)
            } else {
                setConfirmation(.settings(.stay))
            }
        case .revertGeneralSettings:
            guard !isSaving else { return }
            generalSettingsEdit = generalSettings
            settingsValidationError = nil
            settingsStorageError = nil
            settingsNotice = nil
            if confirmation?.windowKind == .settings { confirmation = nil }
        case .systemTimeZoneChanged(let timeZone):
            guard !isSaving else {
                pendingMacTimeZone = timeZone
                return
            }
            let previous = effectiveTimeZoneIdentifier
            let pendingKind = confirmation?.kind
            macTimeZone = timeZone
            if previous != effectiveTimeZoneIdentifier {
                let affected = draftDays.filter { $0.timeZoneIdentifier == previous }
                switchReportTimeZone(from: previous, discarding: affected)
                notice = "Mac 报告时区已变化，已清除旧时区 \(affected.count) 份草稿；目标时区草稿及已保存日报保留。"
            }
            if let pendingKind { setConfirmation(pendingKind) }
        case .requestCloseSettings(let session):
            guard !isSaving, openWindows[.settings] == session else { return }
            if hasGeneralSettingsEdits {
                setConfirmation(.settings(.close(session)))
            } else {
                performWindowEffect(.closeSettings(session: session))
            }
        case .discardSettingsAndContinue(let id):
            guard !isSaving, let pending = confirmation, pending.id == id,
                  case .settings(let continuation) = pending.kind else { return }
            confirmation = nil
            generalSettingsEdit = generalSettings
            settingsValidationError = nil
            settingsStorageError = nil
            completeSettingsContinuation(continuation)
        }
    }

    private func quitAfterPendingSizeWrites() {
        guard pendingSizeWrites > 0 else {
            performWindowEffect(.quit)
            return
        }
        guard quitTask == nil else { return }
        let pending = storageTask
        quitTask = Task {
            await pending?.value
            guard !Task.isCancelled else { return }
            quitTask = nil
            send(.quit)
        }
    }

    private func setConfirmation(_ kind: ReportConfirmation.Kind) {
        switch kind {
        case .overwrite(let day):
            confirmation = ReportConfirmation(
                kind: kind, previousMarkdown: savedReports[day]?.markdown,
                markdown: drafts[day]?.markdown ?? savedReports[day]?.markdown ?? "", draftDays: []
            )
        case .discard(let day):
            confirmation = drafts[day] == nil ? nil : ReportConfirmation(
                kind: kind, previousMarkdown: nil, markdown: nil, draftDays: [day]
            )
        case .close, .quit:
            confirmation = ReportConfirmation(
                kind: kind, previousMarkdown: nil, markdown: nil, draftDays: draftDays
            )
        case .settings(let continuation):
            let quitting: Bool
            if case .quit = continuation { quitting = true } else { quitting = false }
            confirmation = ReportConfirmation(
                kind: kind, previousMarkdown: nil, markdown: nil,
                draftDays: quitting ? draftDays : settingsDraftImpact,
                settings: generalSettingsEdit, oldTimeZoneIdentifier: effectiveTimeZoneIdentifier,
                newTimeZoneIdentifier: editedTimeZoneIdentifier
            )
        }
    }

    private func open(_ kind: AppWindowKind) {
        let session = openWindows[kind] ?? UUID()
        let isNewReport = kind == .report && openWindows[.report] == nil
        if isNewReport {
            if let timeZone = effectiveReportTimeZone {
                selectedDay = ReportDay(date: now(), timeZone: timeZone)
            }
            isHistoryVisible = true
            isPreview = false
        }
        openWindows[kind] = session
        if !isStorageReady, !isLoadingStorage {
            storageError = nil
            isLoadingStorage = true
            storageTask = Task {
                defer { isLoadingStorage = false }
                do {
                    let snapshot = try await storage.load()
                    savedReports = Dictionary(uniqueKeysWithValues: snapshot.reports.map { ($0.day, $0) })
                    reportWindowSize = snapshot.windowSize
                    generalSettings = snapshot.generalSettings
                    generalSettingsEdit = generalSettings
                    if let timeZone = effectiveReportTimeZone {
                        selectedDay = ReportDay(date: now(), timeZone: timeZone)
                    }
                    isStorageReady = true
                    if let reportSession = openWindows[.report] {
                        performWindowEffect(.restoreReportSize(snapshot.windowSize ?? AppWindowConfiguration.report.defaultSize, session: reportSession))
                    }
                } catch {
                    storageError = error as? ReportStorageError ?? .unavailable
                    isStorageReady = false
                }
            }
        }
        if lastAppliedMode != windowMode {
            applyMode()
        }
        performWindowEffect(.present(kind, session: session))
        if isNewReport, isStorageReady {
            performWindowEffect(.restoreReportSize(reportWindowSize ?? AppWindowConfiguration.report.defaultSize, session: session))
        }
    }

    private func saveCurrentReport() {
        let day = selectedDay
        let draft = drafts[day]
        let hasEffectiveEdit = draft.map { !$0.markdown.utf8.elementsEqual($0.baseline.utf8) } ?? false
        let report = SavedDailyReport(
            day: day, markdown: body, savedAt: now(),
            lastEditedAt: hasEffectiveEdit ? draft?.editedAt : savedReports[day]?.lastEditedAt
        )
        isSaving = true
        storageError = nil
        notice = nil
        let previous = storageTask
        storageTask = Task {
            await previous?.value
            do {
                try await storage.save(report)
                savedReports[day] = report
                drafts.removeValue(forKey: day)
                notice = "已保存工作日报"
            } catch {
                storageError = error as? ReportStorageError ?? .writeFailed
            }
            finishSaving()
        }
    }

    private func saveGeneralSettings(continuation: ReportSettingsContinuation) {
        let settings = generalSettingsEdit
        let affectedDays = settingsDraftImpact
        isSaving = true
        settingsStorageError = nil
        settingsNotice = nil
        let previous = storageTask
        storageTask = Task {
            await previous?.value
            do {
                try await storage.saveGeneralSettings(settings)
                let previousTimeZone = effectiveTimeZoneIdentifier
                generalSettings = settings
                generalSettingsEdit = settings
                if previousTimeZone != effectiveTimeZoneIdentifier {
                    switchReportTimeZone(from: previousTimeZone, discarding: affectedDays)
                }
                settingsNotice = "已保存常规设置"
                finishSaving()
                completeSettingsContinuation(continuation)
                return
            } catch {
                settingsStorageError = error as? ReportStorageError ?? .writeFailed
            }
            finishSaving()
        }
    }

    private func finishSaving() {
        isSaving = false
        if let timeZone = pendingMacTimeZone {
            pendingMacTimeZone = nil
            send(.systemTimeZoneChanged(timeZone))
        }
    }

    private static func timeZoneIdentifier(_ timeZone: TimeZone) -> String {
        timeZone.identifier == "GMT" ? "Etc/UTC" : timeZone.identifier
    }

    private func completeSettingsContinuation(_ continuation: ReportSettingsContinuation) {
        switch continuation {
        case .stay: break
        case .page(let page): settingsPage = page
        case .close(let session):
            if openWindows[.settings] == session { performWindowEffect(.closeSettings(session: session)) }
        case .quit:
            drafts.removeAll()
            quitAfterPendingSizeWrites()
        }
    }

    private func switchReportTimeZone(from previous: String?, discarding days: [ReportDay]) {
        reportEditRevision += 1
        if let previous { performContextEffect(.cancelTimeZoneTasks(previous, revision: reportEditRevision)) }
        for day in days { drafts.removeValue(forKey: day) }
        if let timeZone = effectiveReportTimeZone {
            selectedDay = (try? ReportDay(calendarDate: selectedDay.calendarDate, timeZoneIdentifier: Self.timeZoneIdentifier(timeZone)))
                ?? ReportDay(date: now(), timeZone: timeZone)
            if openWindows[.report] != nil { performContextEffect(.rescan(selectedDay, revision: reportEditRevision)) }
        }
        confirmation = nil
    }

    private func applyMode() {
        let mode = windowMode
        performWindowEffect(.applyMode(mode))
        if lastAppliedMode != mode {
            recordWindowMode(mode)
            lastAppliedMode = mode
        }
    }
}
