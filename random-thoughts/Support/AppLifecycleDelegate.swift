import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    let store: IntelligenceStore
    let proximityStore: ProximityLockStore
    private let windowCoordinator: AppWindowCoordinator
    private var menuCommands: AppMenuCommands?

    override init() {
        let store = IntelligenceStore(
            service: IntelligenceService(session: .shared),
            defaults: .standard,
            now: { Date() },
            sleep: { try await Task.sleep(for: .seconds($0)) }
        )
        let proximityStore = ProximityLockStore()
        self.store = store
        self.proximityStore = proximityStore
        windowCoordinator = AppWindowCoordinator(store: store, proximityStore: proximityStore)
        super.init()
    }

    func showSettings() {
        windowCoordinator.showSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        let commands = AppMenuCommands(
            showSettings: windowCoordinator.showSettings,
            isSettingsKeyWindow: { [windowCoordinator] in windowCoordinator.isSettingsKeyWindow }
        )
        menuCommands = commands
        let menu = commands.makeMainMenu()
        app.mainMenu = menu
        app.windowsMenu = menu.items.last?.submenu
        app.setActivationPolicy(.accessory)
        store.startUpdating()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            proximityStore.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowCoordinator.reopenSettingsIfOpen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
