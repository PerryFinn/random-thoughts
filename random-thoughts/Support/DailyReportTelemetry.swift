import CocoaLumberjack

@MainActor
struct DailyReportTelemetry {
    private let log: DDLog

    init(log: DDLog) {
        self.log = log
    }

    static func makeSystemLog() -> DDLog {
        let log = DDLog()
        log.add(DDOSLogger(
            subsystem: "com.perryfinn.random-thoughts",
            category: "DailyReports"
        ))
        return log
    }

    func windowModeChanged(_ mode: AppWindowMode) {
        emit(format: "window_mode_changed mode=%@", text: "window_mode_changed mode=\(mode.rawValue)", event: .windowMode)
    }

    func codexCheckFinished(_ event: CodexCheckEvent) {
        emit(format: "codex_check_finished result=%@ error=%@ version=%@",
             text: "codex_check_finished result=\(event.result.rawValue) error=\(event.error?.rawValue ?? "none") version=\(event.version?.description ?? "unknown")",
             event: .codexCheck)
    }

    private enum Event: String {
        case windowMode = "window_mode_changed"
        case codexCheck = "codex_check_finished"
    }

    private func emit(format: String, text: String, event: Event) {
        let message = DDLogMessage(
            format: format,
            formatted: text,
            level: .info,
            flag: .info,
            context: 0,
            file: "DailyReports",
            function: event.rawValue,
            line: 0,
            tag: nil,
            options: [],
            timestamp: nil
        )
        log.log(asynchronous: true, message: message)
    }
}
