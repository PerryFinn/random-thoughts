import AppKit
import SwiftUI

@main
struct RandomThoughtsApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @State private var store: IntelligenceStore
    @State private var proximityStore: ProximityLockStore

    init() {
        let store = IntelligenceStore()
        let proximityStore = ProximityLockStore()
        _store = State(initialValue: store)
        _proximityStore = State(initialValue: proximityStore)
        store.startUpdating()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            proximityStore.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store, proximityStore: proximityStore)
        } label: {
            Image(
                systemName: proximityStore.latestRSSI == nil
                    ? "brain.head.profile"
                    : "brain.head.profile.fill"
            )
                .accessibilityLabel("随想")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, proximityStore: proximityStore)
        }
    }
}
