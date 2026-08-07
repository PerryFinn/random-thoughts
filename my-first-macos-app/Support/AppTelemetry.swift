import Foundation
import OSLog

enum AppTelemetry {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.perryfinn.my-first-macos-app"

    static let windowing = Logger(subsystem: subsystem, category: "Windowing")
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    static let refresh = Logger(subsystem: subsystem, category: "Refresh")
}
