import SwiftUI

@main
struct RandomThoughtsApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: appDelegate.store, flow: appDelegate.flow, proximityStore: appDelegate.proximityStore)
        } label: {
            Image(
                systemName: appDelegate.proximityStore.latestRSSI == nil
                    ? "brain.head.profile"
                    : "brain.head.profile.fill"
            )
                .accessibilityLabel("随想")
        }
        .menuBarExtraStyle(.window)
    }
}
