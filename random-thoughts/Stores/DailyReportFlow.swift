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
    }

    private(set) var openWindows: [AppWindowKind: UUID] = [:]
    private(set) var selectedDate: Date
    private(set) var isHistoryVisible = true
    let reportTimeZone: TimeZone

    var windowMode: AppWindowMode {
        openWindows.isEmpty ? .menuBar : .foreground
    }

    @ObservationIgnored private let performWindowEffect: (AppWindowEffect) -> Void
    @ObservationIgnored private let recordWindowMode: (AppWindowMode) -> Void
    @ObservationIgnored private var lastAppliedMode: AppWindowMode?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(
        now: @escaping () -> Date,
        timeZone: TimeZone,
        performWindowEffect: @escaping (AppWindowEffect) -> Void,
        recordWindowMode: @escaping (AppWindowMode) -> Void
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.now = now
        reportTimeZone = timeZone
        selectedDate = calendar.startOfDay(for: now())
        self.performWindowEffect = performWindowEffect
        self.recordWindowMode = recordWindowMode
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
            performWindowEffect(.quit)
        case .systemSleep, .systemWake:
            applyMode()
        case .selectDate(let date):
            selectedDate = calendar.startOfDay(for: date)
        case .moveDate(let offset):
            if let date = calendar.date(byAdding: .day, value: offset, to: selectedDate) {
                selectedDate = date
            }
        case .toggleHistory:
            isHistoryVisible.toggle()
        }
    }

    private func open(_ kind: AppWindowKind) {
        if kind == .report, openWindows[.report] == nil {
            selectedDate = calendar.startOfDay(for: now())
            isHistoryVisible = true
        }
        let session = openWindows[kind] ?? UUID()
        openWindows[kind] = session
        if lastAppliedMode != windowMode {
            applyMode()
        }
        performWindowEffect(.present(kind, session: session))
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
