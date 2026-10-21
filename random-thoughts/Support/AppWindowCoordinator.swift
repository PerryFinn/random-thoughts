import AppKit
import SwiftUI

@MainActor
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    weak var flow: DailyReportFlow?

    private struct ManagedWindow {
        let session: UUID
        let controller: NSWindowController
    }

    private let store: IntelligenceStore
    private let proximityStore: ProximityLockStore
    private var windows: [AppWindowKind: ManagedWindow] = [:]
    private var fullScreenTransitions: Set<NSWindow> = []

    init(store: IntelligenceStore, proximityStore: ProximityLockStore) {
        self.store = store
        self.proximityStore = proximityStore
        super.init()
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemTimeZoneChanged), name: .NSSystemTimeZoneDidChange, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func perform(_ effect: AppWindowEffect) {
        switch effect {
        case .applyMode(let mode):
            NSApplication.shared.setActivationPolicy(mode == .foreground ? .regular : .accessory)
        case .present(let kind, let session):
            present(kind, session: session)
        case .hide:
            NSApplication.shared.hide(nil)
        case .minimizeReport:
            windows[.report]?.controller.window?.miniaturize(nil)
        case .closeKeyWindow:
            NSApplication.shared.keyWindow?.performClose(nil)
        case .closeReport(let session):
            if windows[.report]?.session == session { windows[.report]?.controller.window?.close() }
        case .closeSettings(let session):
            if windows[.settings]?.session == session { windows[.settings]?.controller.window?.close() }
        case .restoreReportSize(let size, let session):
            if windows[.report]?.session == session, let window = windows[.report]?.controller.window {
                restoreReportSize(size, window: window)
            }
        case .quit:
            NSApplication.shared.terminate(nil)
        case .openReportDataDirectory(let directory):
            NSWorkspace.shared.open(directory)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = windows.first(where: { $0.value.controller.window === sender }) else { return true }
        if entry.key == .report {
            flow?.send(.requestCloseReport(entry.value.session))
        } else {
            flow?.send(.requestCloseSettings(entry.value.session))
        }
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let report = windows[.report], report.controller.window === window,
              !window.isMiniaturized, !window.styleMask.contains(.fullScreen),
              !fullScreenTransitions.contains(window) else { return }
        flow?.send(.normalReportSizeChanged(window.contentRect(forFrameRect: window.frame).size, session: report.session))
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow { fullScreenTransitions.insert(window) }
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow { fullScreenTransitions.remove(window) }
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow { fullScreenTransitions.insert(window) }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow { fullScreenTransitions.remove(window) }
        windowDidResize(notification)
    }

    var keyWindowKind: AppWindowKind? {
        windows.first { $0.value.controller.window === NSApplication.shared.keyWindow }?.key
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = windows.first(where: { $0.value.controller.window === window }) else {
            return
        }
        windows.removeValue(forKey: entry.key)
        fullScreenTransitions.remove(window)
        flow?.send(.windowClosed(entry.key, session: entry.value.session))
    }

    private func present(_ kind: AppWindowKind, session: UUID) {
        let window: NSWindow
        if let existing = windows[kind]?.controller.window {
            window = existing
        } else {
            guard let flow else { return }
            let configuration = kind == .report ? AppWindowConfiguration.report : .settings
            var style: NSWindow.StyleMask = [.titled, .closable]
            if configuration.canResize { style.insert(.resizable) }
            if configuration.canMinimize { style.insert(.miniaturizable) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: configuration.defaultSize),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = kind == .report ? "工作日报" : "设置"
            window.identifier = NSUserInterfaceItemIdentifier(kind == .report ? "daily-report" : "settings")
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.tabbingMode = .disallowed
            window.collectionBehavior = configuration.canFullScreen ? .fullScreenPrimary : .fullScreenNone
            let content: AnyView
            switch kind {
            case .report:
                content = AnyView(DailyReportView(flow: flow))
            case .settings:
                content = AnyView(SettingsView(
                    flow: flow,
                    intelligenceContent: AnyView(IntelligenceSettingsView(store: store)),
                    proximityContent: AnyView(ProximitySettingsView(store: proximityStore))
                ))
            }
            window.contentView = NSHostingView(rootView: content)
            window.contentMinSize = configuration.minimumSize
            if !configuration.canResize {
                window.contentMaxSize = configuration.defaultSize
            }
            window.setContentSize(configuration.defaultSize)
            window.delegate = self
            windows[kind] = ManagedWindow(session: session, controller: NSWindowController(window: window))
            if kind == .report { window.center() }
        }
        if kind == .settings { centerOnActiveDisplay(window) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
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

    private func restoreReportSize(_ size: CGSize, window: NSWindow) {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let available = window.contentRect(forFrameRect: visible).size
        let configuration = AppWindowConfiguration.report
        window.contentMinSize = configuration.restoredContentSize(stored: configuration.minimumSize, visibleContentSize: available)
        window.setContentSize(configuration.restoredContentSize(stored: size, visibleContentSize: available))
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
    }

    @objc private func systemWillSleep() { flow?.send(.systemSleep) }
    @objc private func systemDidWake() {
        systemTimeZoneChanged()
        flow?.send(.systemWake)
    }
    @objc private func systemTimeZoneChanged() { flow?.send(.systemTimeZoneChanged(.current)) }
}
