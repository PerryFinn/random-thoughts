import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    let store: IntelligenceStore
    let proximityStore: ProximityLockStore
    let flow: DailyReportFlow
    private let windowCoordinator: AppWindowCoordinator
    private var menuCommands: AppMenuCommands?
    private var hasFinishedLaunching = false

    override init() {
        let store = IntelligenceStore(
            service: IntelligenceService(session: .shared),
            defaults: .standard,
            now: { Date() },
            sleep: { try await Task.sleep(for: .seconds($0)) }
        )
        let proximityStore = ProximityLockStore()
        let windowCoordinator = AppWindowCoordinator(store: store, proximityStore: proximityStore)
        let telemetry = DailyReportTelemetry(log: DailyReportTelemetry.makeSystemLog())
        self.store = store
        self.proximityStore = proximityStore
        self.windowCoordinator = windowCoordinator
        flow = DailyReportFlow(
            now: { Date() },
            timeZone: .current,
            performWindowEffect: { windowCoordinator.perform($0) },
            recordWindowMode: { telemetry.windowModeChanged($0) }
        )
        super.init()
        windowCoordinator.flow = flow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let reason = AppLaunchReasonDetector.reason(for: NSAppleEventManager.shared().currentAppleEvent)
        let commands = AppMenuCommands(flow: flow, keyWindowKind: { [windowCoordinator] in
            windowCoordinator.keyWindowKind
        })
        menuCommands = commands
        let menu = commands.makeMainMenu()
        NSApplication.shared.mainMenu = menu
        NSApplication.shared.windowsMenu = menu.items.last?.submenu
        flow.send(.launch(reason))
        hasFinishedLaunching = true
        store.startUpdating()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            proximityStore.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasFinishedLaunching { flow.send(.reactivate) }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
