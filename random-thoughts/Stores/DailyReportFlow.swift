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
        case editBody(String, day: ReportDay, session: UUID)
        case save
        case copyMarkdown
        case confirm(UUID)
        case cancelConfirmation
        case requestDiscardDraft
        case requestCloseReport(UUID)
        case setPreview(Bool)
        case normalReportSizeChanged(CGSize, session: UUID)
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
    private var drafts: [ReportDay: Draft] = [:]
    private var pendingSizeWrites = 0

    var reportTimeZone: TimeZone { selectedDay.timeZone }
    var selectedDate: Date { selectedDay.start }
    var body: String { drafts[selectedDay]?.markdown ?? savedReports[selectedDay]?.markdown ?? "" }
    var hasDraft: Bool { drafts[selectedDay] != nil }
    var draftDays: [ReportDay] {
        drafts.keys.sorted { ($0.calendarDate, $0.timeZoneIdentifier) < ($1.calendarDate, $1.timeZoneIdentifier) }
    }
    var canTerminate: Bool { !isSaving && pendingSizeWrites == 0 && drafts.isEmpty }
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
    @ObservationIgnored private let recordWindowMode: (AppWindowMode) -> Void
    @ObservationIgnored private var lastAppliedMode: AppWindowMode?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaultTimeZone: TimeZone
    @ObservationIgnored private let storage: any DailyReportStorage
    @ObservationIgnored private let copyMarkdown: (String) -> Void
    @ObservationIgnored private var storageTask: Task<Void, Never>?
    @ObservationIgnored private var quitTask: Task<Void, Never>?

    init(
        storage: any DailyReportStorage,
        now: @escaping () -> Date,
        timeZone: TimeZone,
        performWindowEffect: @escaping (AppWindowEffect) -> Void,
        recordWindowMode: @escaping (AppWindowMode) -> Void,
        copyMarkdown: @escaping (String) -> Void
    ) {
        self.storage = storage
        self.now = now
        defaultTimeZone = timeZone
        selectedDay = ReportDay(date: now(), timeZone: timeZone)
        self.performWindowEffect = performWindowEffect
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
            guard openWindows[kind] == session else { return }
            openWindows.removeValue(forKey: kind)
            if kind == .report {
                drafts.removeAll()
                confirmation = nil
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
            if drafts.isEmpty {
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
            selectedDay = ReportDay(date: date, timeZone: reportTimeZone)
            confirmation = nil
        case .moveDate(let offset):
            if let date = selectedDay.calendar.date(byAdding: .day, value: offset, to: selectedDate) {
                selectedDay = ReportDay(date: date, timeZone: reportTimeZone)
                confirmation = nil
            }
        case .toggleHistory:
            isHistoryVisible.toggle()
        case .selectReportDay(let day):
            selectedDay = day
            confirmation = nil
        case .editBody(let markdown, let day, let session):
            guard isStorageReady, !isSaving, openWindows[.report] == session, day == selectedDay,
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
            guard isStorageReady, !isSaving, openWindows[.report] != nil else { return }
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
        }
    }

    private func open(_ kind: AppWindowKind) {
        let session = openWindows[kind] ?? UUID()
        let isNewReport = kind == .report && openWindows[.report] == nil
        if isNewReport {
            selectedDay = ReportDay(date: now(), timeZone: defaultTimeZone)
            isHistoryVisible = true
            isPreview = false
            if !isStorageReady {
                storageError = nil
                storageTask = Task {
                    do {
                        let snapshot = try await storage.load()
                        guard openWindows[.report] == session else { return }
                        savedReports = Dictionary(uniqueKeysWithValues: snapshot.reports.map { ($0.day, $0) })
                        reportWindowSize = snapshot.windowSize
                        isStorageReady = true
                        performWindowEffect(.restoreReportSize(snapshot.windowSize ?? AppWindowConfiguration.report.defaultSize, session: session))
                    } catch {
                        guard openWindows[.report] == session else { return }
                        storageError = error as? ReportStorageError ?? .unavailable
                        isStorageReady = false
                    }
                }
            }
        }
        openWindows[kind] = session
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
            isSaving = false
        }
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
