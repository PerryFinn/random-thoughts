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
        let message = DDLogMessage(
            format: "window_mode_changed mode=%@",
            formatted: "window_mode_changed mode=\(mode.rawValue)",
            level: .info,
            flag: .info,
            context: 0,
            file: "DailyReports",
            function: "window_mode_changed",
            line: 0,
            tag: nil,
            options: [],
            timestamp: nil
        )
        log.log(asynchronous: true, message: message)
    }
}
