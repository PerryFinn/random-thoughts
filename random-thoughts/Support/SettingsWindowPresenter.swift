import AppKit
import OSLog

@MainActor
enum SettingsWindowPresenter {
    private static var isFocusAttemptActive = false

    static func bringToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard !isFocusAttemptActive else {
            AppTelemetry.windowing.debug("Coalesced settings focus request")
            return
        }

        isFocusAttemptActive = true
        AppTelemetry.windowing.info("Settings focus requested")

        Task { @MainActor in
            defer { isFocusAttemptActive = false }

            for delay in [0, 50, 150] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }

                NSApplication.shared.activate(ignoringOtherApps: true)
                if focusSettingsWindow() {
                    AppTelemetry.windowing.info("Settings window focused")
                    return
                }
            }

            AppTelemetry.windowing.error("Settings window unavailable after focus retries")
        }
    }

    @discardableResult
    private static func focusSettingsWindow() -> Bool {
        guard let window = NSApplication.shared.windows.first(where: { window in
            window.canBecomeKey
                && window.styleMask.contains(.titled)
                && !window.styleMask.contains(.nonactivatingPanel)
        }) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
