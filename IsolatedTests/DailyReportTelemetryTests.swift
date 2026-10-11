import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportTelemetryTests {
    @Test func codexDiagnosticsOnlyLogFixedCodesAndParsedNumericVersions() {
        let log = DDLog()
        let memory = MemoryWindowLogger()
        log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        telemetry.codexCheckFinished(CodexCheckEvent(result: .success, error: nil,
            version: CodexVersion.fromUserAgent("random_thoughts/9.8.7 (USER_AGENT_SECRET_25)")))
        for error in CodexSourceError.allCases {
            telemetry.codexCheckFinished(CodexCheckEvent(result: error == .cancelled ? .cancelled : .failure, error: error, version: nil))
        }
        log.flushLog()
        let messages = memory.snapshot()
        #expect(messages.first?.message == "codex_check_finished result=success error=none version=9.8.7")
        #expect(messages.count == CodexSourceError.allCases.count + 1)
        for message in messages {
            #expect(message.messageFormat == "codex_check_finished result=%@ error=%@ version=%@")
            #expect(!message.message.contains("SECRET_25"))
            #expect(message.file == "DailyReports")
            #expect(message.function == "codex_check_finished")
            #expect(message.line == 0)
            #expect(message.context == 0)
            #expect(message.representedObject == nil)
        }
        #expect(CodexVersion("VERSION_SECRET_25") == nil)
        #expect(CodexVersion.fromUserAgent("https://ENDPOINT_SECRET_25/9.8.7") == nil)
        #expect(CodexVersion.fromUserAgent("random_thoughts/9.8.7BODY_SECRET_25") == nil)
    }

    @Test func capturesOnlyWindowModesAndFixedMetadata() {
        let log = DDLog()
        let memory = MemoryWindowLogger()
        log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)

        telemetry.windowModeChanged(.foreground)
        telemetry.windowModeChanged(.menuBar)
        log.flushLog()
        let messages = memory.snapshot()

        #expect(messages.map(\.message) == [
            "window_mode_changed mode=foreground",
            "window_mode_changed mode=menu_bar"
        ])
        for message in messages {
            #expect(message.messageFormat == "window_mode_changed mode=%@")
            #expect(message.file == "DailyReports")
            #expect(message.function == "window_mode_changed")
            #expect(message.line == 0)
            #expect(message.context == 0)
            #expect(message.representedObject == nil)
            #expect(message.level == .info)
            #expect(message.flag == .info)
        }
        #expect(memory.logFormatter == nil)
    }

    @Test func productionRegistersOnlyTheSystemLoggerWithoutFormatter() throws {
        let log = DailyReportTelemetry.makeSystemLog()
        #expect(log.allLoggers.count == 1)
        let logger = try #require(log.allLoggers.first as? DDOSLogger)
        #expect(logger.logFormatter == nil)
    }
}

private final class MemoryWindowLogger: DDAbstractLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [DDLogMessage] = []

    override func log(message: DDLogMessage) {
        lock.withLock { messages.append(message) }
    }

    func snapshot() -> [DDLogMessage] {
        lock.withLock { messages }
    }
}
