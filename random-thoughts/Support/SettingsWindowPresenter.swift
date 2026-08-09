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
            var didFocusWindow = false

            for delay in [0, 50, 150] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }

                NSApplication.shared.activate(ignoringOtherApps: true)
                if focusSettingsWindow() {
                    didFocusWindow = true
                }
            }

            if didFocusWindow {
                AppTelemetry.windowing.info("Settings window focused")
            } else {
                AppTelemetry.windowing.error("Settings window unavailable after focus retries")
            }
        }
    }

    @discardableResult
    private static func focusSettingsWindow() -> Bool {
        let candidates = NSApplication.shared.windows.filter { window in
            window.canBecomeKey
                && window.styleMask.contains(.titled)
                && !window.styleMask.contains(.nonactivatingPanel)
        }
        guard let window = candidates.first(where: { window in
            window.title.localizedCaseInsensitiveContains("settings")
                || window.title.localizedCaseInsensitiveContains("设置")
        }) ?? candidates.first else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
