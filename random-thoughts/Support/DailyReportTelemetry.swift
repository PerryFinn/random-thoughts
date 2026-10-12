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

    func sessionScanFinished(_ event: CodexScanEvent) {
        emit(format: "session_scan_finished result=%@ candidates=%d succeeded=%d failed=%d",
             text: "session_scan_finished result=\(event.result.rawValue) candidates=\(event.candidates) succeeded=\(event.succeeded) failed=\(event.failed)",
             event: .sessionScan)
    }

    func storageFinished(_ event: AIServiceStorageEvent) {
        emit(format: "report_storage_finished operation=%@ result=%@ schema=%d credential_format=%d",
             text: "report_storage_finished operation=\(event.operation.rawValue) result=\(event.result.rawValue) schema=4 credential_format=1",
             event: .storage)
    }

    private enum Event: String {
        case windowMode = "window_mode_changed"
        case codexCheck = "codex_check_finished"
        case sessionScan = "session_scan_finished"
        case storage = "report_storage_finished"
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
