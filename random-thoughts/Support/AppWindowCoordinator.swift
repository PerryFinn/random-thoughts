import AppKit
import SwiftUI

@MainActor
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    private let store: IntelligenceStore
    private let proximityStore: ProximityLockStore
    private let settingsSelection = SettingsView.Selection()
    private var settingsWindow: NSWindow?

    init(store: IntelligenceStore, proximityStore: ProximityLockStore) {
        self.store = store
        self.proximityStore = proximityStore
    }

    var isSettingsKeyWindow: Bool {
        settingsWindow?.isKeyWindow == true
    }

    func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }

        let size = SettingsView.windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = .fullScreenNone
        window.contentView = NSHostingView(rootView: SettingsView(
            selection: settingsSelection,
            intelligenceContent: AnyView(IntelligenceSettingsView(store: store)),
            proximityContent: AnyView(ProximitySettingsView(store: proximityStore))
        ))
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.delegate = self
        settingsWindow = window
        present(window)
    }

    func reopenSettingsIfOpen() {
        if let settingsWindow {
            present(settingsWindow)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        settingsWindow = nil
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func present(_ window: NSWindow) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        centerOnActiveDisplay(window)
        app.unhide(nil)
        app.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func centerOnActiveDisplay(_ window: NSWindow) {
        guard let screen = NSApplication.shared.keyWindow?.screen
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
    }
}
