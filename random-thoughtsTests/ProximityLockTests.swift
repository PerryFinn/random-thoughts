import Foundation
import Testing
@testable import random_thoughts

struct ProximityLockTests {
    @Test func delaysAwayTransitionUntilConfiguredInterval() {
        var detector = ProximityPresenceDetector()
        var configuration = ProximityConfiguration.default
        configuration.lockDelay = 5
        let start = Date(timeIntervalSince1970: 1_000)
        detector.reset(at: start)

        let sample = detector.receive(
            rssi: -90,
            at: start,
            configuration: configuration
        )
        #expect(sample.transition == nil)
        #expect(detector.tick(at: start.addingTimeInterval(4), configuration: configuration).transition == nil)
        #expect(
            detector.tick(
                at: start.addingTimeInterval(5),
                configuration: configuration
            ).transition == .away
        )
    }

    @Test func strongerSignalCancelsPendingAwayTransition() {
        var detector = ProximityPresenceDetector()
        var configuration = ProximityConfiguration.default
        configuration.lockDelay = 5
        let start = Date(timeIntervalSince1970: 2_000)
        detector.reset(at: start)

        _ = detector.receive(rssi: -90, at: start, configuration: configuration)
        _ = detector.receive(
            rssi: -60,
            at: start.addingTimeInterval(3),
            configuration: configuration
        )

        #expect(
            detector.tick(
                at: start.addingTimeInterval(10),
                configuration: configuration
            ).transition == nil
        )
        #expect(detector.isPresent)
    }

    @Test func reportsSignalLossOnlyOnceAndClosesAgainWhenDeviceReturns() {
        var detector = ProximityPresenceDetector()
        var configuration = ProximityConfiguration.default
        configuration.signalTimeout = 30
        let start = Date(timeIntervalSince1970: 3_000)
        detector.reset(at: start)

        let firstTick = detector.tick(
            at: start.addingTimeInterval(30),
            configuration: configuration
        )
        let secondTick = detector.tick(
            at: start.addingTimeInterval(31),
            configuration: configuration
        )
        let close = detector.receive(
            rssi: -50,
            at: start.addingTimeInterval(32),
            configuration: configuration
        )

        #expect(firstTick.signalWasLost)
        #expect(firstTick.transition == .lost)
        #expect(!secondTick.signalWasLost)
        #expect(close.transition == .close)
        #expect(detector.isPresent)
    }

    @Test func scanPolicyStopsAfterActiveMonitoringLeavesDevicePicker() {
        #expect(
            ProximityBluetoothScanPolicy.shouldScan(
                isDeviceDiscoveryRequested: true,
                hasSelectedDevice: true,
                isActivelyReadingRSSI: true
            )
        )
        #expect(
            !ProximityBluetoothScanPolicy.shouldScan(
                isDeviceDiscoveryRequested: false,
                hasSelectedDevice: true,
                isActivelyReadingRSSI: true
            )
        )
        #expect(
            ProximityBluetoothScanPolicy.shouldScan(
                isDeviceDiscoveryRequested: false,
                hasSelectedDevice: true,
                isActivelyReadingRSSI: false
            )
        )
        #expect(
            !ProximityBluetoothScanPolicy.shouldScan(
                isDeviceDiscoveryRequested: false,
                hasSelectedDevice: false,
                isActivelyReadingRSSI: false
            )
        )
    }

    @Test func manualUnlockResumesPlaybackWhenAutomaticUnlockIsDisabled() {
        let actions = ProximityScreenUnlockPolicy.actions(
            elapsedSinceAutomaticUnlock: 11,
            automaticUnlockEnabled: false
        )

        #expect(!actions.shouldRunIntrudedScript)
        #expect(actions.shouldResumePlayback)
    }

    @Test func updateCheckerOnlyAcceptsNewerVersions() {
        #expect(ReleaseUpdateChecker.isNewerVersion("v1.2.0", than: "1.1.9"))
        #expect(!ReleaseUpdateChecker.isNewerVersion("1.0", than: "1.0"))
        #expect(!ReleaseUpdateChecker.isNewerVersion("v1.0.0", than: "1.0"))
        #expect(!ReleaseUpdateChecker.isNewerVersion("0.9.9", than: "1.0"))
    }

    @Test @MainActor func settingsWindowKeepsMigratedLayoutSize() {
        #expect(SettingsView.windowSize == CGSize(width: 860, height: 620))
    }

    @Test @MainActor func startChecksButDoesNotPromptForAccessibility() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-permission-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let system = FakeProximitySystemController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: FakeBluetoothController(),
            systemController: system
        )

        store.start()
        #expect(system.accessibilityPermissionRequests == 0)

        store.requestAccessibilityPermission()
        #expect(system.accessibilityPermissionRequests == 1)
    }

    @Test @MainActor func awayEventLocksNotifiesAndRunsScript() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-away-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let system = FakeProximitySystemController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: system
        )
        var configuration = ProximityConfiguration.default
        configuration.selectedDeviceID = UUID()
        store.updateConfiguration(configuration)
        store.start()

        bluetooth.send(.state(.poweredOn))
        bluetooth.send(.signal(rssi: -86, active: true))
        bluetooth.send(.presence(isPresent: false, reason: .away))

        #expect(system.lockRequests == 1)
        #expect(system.notifiedReasons == [.away])
        #expect(system.scriptEvents == ["away:-86"])
    }

    @Test @MainActor func presenceEventsDoNothingWithoutSelectedDevice() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-no-device-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let system = FakeProximitySystemController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: system
        )
        store.start()

        bluetooth.send(.presence(isPresent: false, reason: .lost))

        #expect(system.lockRequests == 0)
        #expect(system.notifiedReasons.isEmpty)
        #expect(system.scriptEvents.isEmpty)
    }

    @Test @MainActor func stalePresenceEventDoesNotLockWhileBluetoothIsOff() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-powered-off-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let system = FakeProximitySystemController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: system
        )
        var configuration = ProximityConfiguration.default
        configuration.selectedDeviceID = UUID()
        store.updateConfiguration(configuration)
        store.start()

        bluetooth.send(.state(.poweredOff))
        bluetooth.send(.presence(isPresent: false, reason: .lost))

        #expect(system.lockRequests == 0)
        #expect(system.notifiedReasons.isEmpty)
    }

    @Test @MainActor func closeEventTypesStoredPasswordIntoLockedScreen() async throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-unlock-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let system = FakeProximitySystemController()
        system.screenLocked = true
        system.password = "secret"
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: system
        )
        var configuration = ProximityConfiguration.default
        configuration.selectedDeviceID = UUID()
        store.updateConfiguration(configuration)
        store.start()

        bluetooth.send(.state(.poweredOn))
        bluetooth.send(.presence(isPresent: false, reason: .lost))
        bluetooth.send(.presence(isPresent: true, reason: .close))
        try? await Task.sleep(for: .milliseconds(650))

        #expect(system.enteredPasswords == ["secret"])
        #expect(system.scriptEvents == ["unlocked:none"])
    }

    @Test @MainActor func awayEventCancelsPendingPasswordEntry() async throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-cancel-unlock-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let system = FakeProximitySystemController()
        system.screenLocked = true
        system.password = "secret"
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: system
        )
        var configuration = ProximityConfiguration.default
        configuration.selectedDeviceID = UUID()
        store.updateConfiguration(configuration)
        store.start()

        bluetooth.send(.state(.poweredOn))
        bluetooth.send(.presence(isPresent: true, reason: .close))
        bluetooth.send(.presence(isPresent: false, reason: .away))
        try? await Task.sleep(for: .milliseconds(650))

        #expect(system.enteredPasswords.isEmpty)
        #expect(system.scriptEvents.isEmpty)
    }
}

@MainActor
private final class FakeBluetoothController: ProximityBluetoothControlling {
    var eventHandler: ((ProximityBluetoothEvent) -> Void)?
    var configuration = ProximityConfiguration.default
    var monitoredDeviceID: UUID?

    func apply(configuration: ProximityConfiguration) {
        self.configuration = configuration
    }

    func startMonitoring(deviceID: UUID?) {
        monitoredDeviceID = deviceID
    }

    func startScanning() {}
    func stopScanning() {}

    func send(_ event: ProximityBluetoothEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class FakeProximitySystemController: ProximitySystemControlling {
    var screenLocked = false
    var password: String?
    var accessibilityTrusted = true
    var launchAtLoginRequested = false
    var lockRequests = 0
    var notifiedReasons: [ProximityPresenceReason] = []
    var scriptEvents: [String] = []
    var enteredPasswords: [String] = []
    var accessibilityPermissionRequests = 0

    var isScreenLocked: Bool { screenLocked }
    var isAccessibilityTrusted: Bool { accessibilityTrusted }
    var containsPassword: Bool { password != nil }
    var isLaunchAtLoginRequested: Bool { launchAtLoginRequested }
    var applicationScriptURL: URL? { URL(fileURLWithPath: "/tmp/event") }

    func requestAccessibilityPermission() { accessibilityPermissionRequests += 1 }
    func promptForPassword() -> String? { password }
    func storePassword(_ password: String) throws { self.password = password }
    func fetchPassword() throws -> String? { password }
    func deletePassword() throws { password = nil }

    func lockScreen(useScreensaver: Bool, turnOffDisplay: Bool) throws {
        lockRequests += 1
        screenLocked = true
    }

    func wakeDisplay() {}
    func sendEscapeKey() {}
    func enterPassword(_ password: String) { enteredPasswords.append(password) }
    func pauseNowPlaying(completion: @escaping (Bool) -> Void) { completion(false) }
    func resumeNowPlaying() {}

    func runEventScript(argument: String, rssi: Int?) {
        scriptEvents.append("\(argument):\(rssi.map(String.init) ?? "none")")
    }

    func openApplicationScriptsFolder() {}
    func requestNotificationAuthorization() {}
    func notifyLocked(reason: ProximityPresenceReason) { notifiedReasons.append(reason) }
    func removeLockNotification() {}
    func notifyUpdateAvailable(version: String, releasesURL: URL) {}
    func setLaunchAtLogin(_ enabled: Bool) throws { launchAtLoginRequested = enabled }
    func presentBluetoothPowerWarning() {}
}
