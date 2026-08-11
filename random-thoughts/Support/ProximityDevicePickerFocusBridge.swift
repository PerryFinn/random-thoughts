import AppKit
import SwiftUI

struct ProximityDevicePickerFocusBridge: NSViewRepresentable {
    let focusSearch: @MainActor () -> Void

    func makeNSView(context: Context) -> ProximityDevicePickerFocusView {
        ProximityDevicePickerFocusView(focusSearch: focusSearch)
    }

    func updateNSView(
        _ nsView: ProximityDevicePickerFocusView,
        context: Context
    ) {
        nsView.focusSearch = focusSearch
    }

    static func dismantleNSView(
        _ nsView: ProximityDevicePickerFocusView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}

final class ProximityDevicePickerFocusView: NSView {
    var focusSearch: @MainActor () -> Void

    private weak var configuredWindow: NSWindow?
    private var keyDownMonitor: Any?

    init(focusSearch: @escaping @MainActor () -> Void) {
        self.focusSearch = focusSearch
        super.init(frame: .zero)
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure(for: window)
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard Self.isFindShortcut(event) else { return event }
        focusSearch()
        return nil
    }

    func stopMonitoring() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if configuredWindow?.initialFirstResponder === self {
            configuredWindow?.initialFirstResponder = nil
        }
        configuredWindow = nil
    }

    private func configure(for window: NSWindow?) {
        guard configuredWindow !== window else { return }
        stopMonitoring()
        guard let window else { return }

        configuredWindow = window
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self, weak window] event in
            guard let self, event.window === window else { return event }
            return self.handleKeyDown(event)
        }
    }

    private static func isFindShortcut(_ event: NSEvent) -> Bool {
        let semanticModifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])
        return semanticModifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "f"
    }
}
