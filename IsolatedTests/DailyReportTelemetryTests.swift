import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportTelemetryTests {
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
