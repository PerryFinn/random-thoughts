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
             text: "report_storage_finished operation=\(event.operation.rawValue) result=\(event.result.rawValue) schema=5 credential_format=2",
             event: .storage)
    }

    func validationFinished(_ event: AIValidationEvent) {
        emit(format: "ai_validation_finished service=%@ stage=%@ result=%@ capability=%@",
             text: "ai_validation_finished service=\(event.service.rawValue) stage=\(event.stage.rawValue) result=\(event.result.rawValue) capability=\(event.capability.rawValue)",
             event: .validation)
    }

    func generationChanged(_ value: ReportGenerationEvent) {
        let event: Event
        switch value.kind {
        case .started: event = .generationStarted
        case .stageChanged: event = .generationStage
        case .finished: event = .generationFinished
        }
        emit(format: "report_generation event=%@ path=%@ stage=%@ result=%@ input_tokens=%d reason=%@ plan_min=%d plan_max=%d layer=%d completed=%d in_flight=%d tokenizer=0.12.1",
             text: "\(value.kind.rawValue) path=\(value.path.rawValue) stage=\(value.stage.rawValue) result=\(value.result.rawValue) input_tokens=\(value.inputTokens) reason=\(value.error?.rawValue ?? "none") plan_min=\(value.scale?.minimumRequests ?? 0) plan_max=\(value.scale?.maximumRequests ?? 0) layer=\(value.layer) completed=\(value.completedRequests) in_flight=\(value.inFlightRequests) tokenizer=0.12.1",
             event: event)
    }

    private enum Event: String {
        case windowMode = "window_mode_changed"
        case codexCheck = "codex_check_finished"
        case sessionScan = "session_scan_finished"
        case storage = "report_storage_finished"
        case validation = "ai_validation_finished"
        case generationStarted = "report_generation_started"
        case generationStage = "report_generation_stage_changed"
        case generationFinished = "report_generation_finished"
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
