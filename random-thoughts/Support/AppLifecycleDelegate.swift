import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep a menu-bar-only appearance while allowing CoreBluetooth to run as a
        // regular application during launch and system sleep transitions.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
