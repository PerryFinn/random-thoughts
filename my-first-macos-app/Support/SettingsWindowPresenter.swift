import AppKit

@MainActor
enum SettingsWindowPresenter {
    static func bringToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task { @MainActor in
            for delay in [0, 50, 150] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }

                NSApplication.shared.activate(ignoringOtherApps: true)
                if focusSettingsWindow() {
                    return
                }
            }
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
