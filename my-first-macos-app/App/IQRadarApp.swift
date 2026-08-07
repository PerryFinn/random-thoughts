import SwiftUI

@main
struct IQRadarApp: App {
    @State private var store: IntelligenceStore

    init() {
        let store = IntelligenceStore()
        _store = State(initialValue: store)
        store.startUpdating()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            Image(systemName: "brain.head.profile")
                .accessibilityLabel("IQ Radar")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
