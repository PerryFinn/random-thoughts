import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarStatusItem: NSObject {
    private let item: NSStatusItem
    private let presentation = Presentation()

    init(store: IntelligenceStore, proximityStore: ProximityLockStore, showSettings: @escaping () -> Void) {
        let statusBar = NSStatusBar.system
        item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let view = NSHostingView(rootView: StatusLabel(
            store: store,
            proximityStore: proximityStore,
            showSettings: showSettings,
            presentation: presentation
        ))
        // Keep the status item out of the default button's layout while AppKit attaches it to a display.
        let side = statusBar.thickness
        view.sizingOptions = []
        view.frame.size = NSSize(width: side, height: side)
        item.view = view
        item.target = self
        item.action = #selector(togglePanel)
        item.behavior = .terminationOnRemoval
    }

    @objc private func togglePanel() {
        presentation.isPresented.toggle()
    }

    @Observable
    fileprivate final class Presentation {
        var isPresented = false
    }

    private struct StatusLabel: View {
        let store: IntelligenceStore
        let proximityStore: ProximityLockStore
        let showSettings: () -> Void
        @Bindable var presentation: Presentation

        var body: some View {
            Image(systemName: proximityStore.latestRSSI == nil ? "brain.head.profile" : "brain.head.profile.fill")
                .accessibilityLabel("随想")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .popover(isPresented: $presentation.isPresented, arrowEdge: .top) {
                    MenuBarPanel(store: store, showSettings: showSettings, proximityStore: proximityStore)
                }
        }
    }
}
