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

    @Test func advertisedBluetoothNameTakesPriority() {
        let name = ProximityDeviceNameResolver.resolve(
            id: UUID(),
            advertisedName: "  Perry 的 iPhone  ",
            peripheralName: "iPhone",
            manufacturer: "Apple Inc.",
            model: "iPhone14,2",
            beaconDescription: nil
        )

        #expect(name == "Perry 的 iPhone")
    }

    @Test func specificAppleModelReplacesGenericBluetoothName() {
        let name = ProximityDeviceNameResolver.resolve(
            id: UUID(),
            advertisedName: "iPhone",
            peripheralName: "iPhone",
            manufacturer: "Apple Inc.",
            model: "iPhone14,2",
            beaconDescription: nil
        )

        #expect(name == "iPhone 13 Pro")
    }

    @Test func genericDeviceTypeTakesPriorityOverManufacturerAlone() {
        let name = ProximityDeviceNameResolver.resolve(
            id: UUID(),
            advertisedName: "iPhone",
            peripheralName: nil,
            manufacturer: "Apple Inc.",
            model: nil,
            beaconDescription: nil
        )

        #expect(name == "iPhone")
    }

    @Test func unnamedBluetoothDeviceUsesShortIdentifier() throws {
        let id = try #require(UUID(uuidString: "12345678-1234-1234-1234-1234567890AB"))
        let name = ProximityDeviceNameResolver.resolve(
            id: id,
            advertisedName: nil,
            peripheralName: nil,
            manufacturer: nil,
            model: nil,
            beaconDescription: nil
        )

        #expect(name == "未知蓝牙设备 · 1234")
    }

    @Test @MainActor func devicePickerKeepsExistingOrderWhenSignalRankingChanges() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-picker-order-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstID = UUID()
        let secondID = UUID()
        let newID = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        bluetooth.send(
            .devices([
                ProximityDevice(id: firstID, name: "第一台", rssi: -40),
                ProximityDevice(id: secondID, name: "第二台", rssi: -60)
            ])
        )
        store.beginDeviceSelection()
        defer { store.endDeviceSelection() }

        bluetooth.send(
            .devices([
                ProximityDevice(id: secondID, name: "第二台", rssi: -35),
                ProximityDevice(id: firstID, name: "第一台", rssi: -80),
                ProximityDevice(id: newID, name: "新设备", rssi: -45)
            ])
        )

        #expect(store.devicePickerEntries.map(\.id) == [firstID, secondID, newID])
        #expect(store.devicePickerEntries.map(\.rssi) == [-80, -35, -45])
    }

    @Test @MainActor func devicePickerKeepsMissingDeviceAsTemporarilyUnavailable() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-picker-offline-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let visibleID = UUID()
        let missingID = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        bluetooth.send(
            .devices([
                ProximityDevice(id: visibleID, name: "在线设备", rssi: -48),
                ProximityDevice(id: missingID, name: "间歇设备", rssi: -65)
            ])
        )
        store.beginDeviceSelection()
        defer { store.endDeviceSelection() }

        bluetooth.send(
            .devices([ProximityDevice(id: visibleID, name: "在线设备", rssi: -50)])
        )

        let missing = try #require(store.devicePickerEntries.first { $0.id == missingID })
        #expect(missing.rssi == nil)
        #expect(
            missing.signal(at: Date(), bluetoothPoweredOn: true) == .unavailable
        )
    }

    @Test @MainActor func devicePickerPinsOfflineSelectedDeviceToTop() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-picker-selected-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let selectedID = UUID()
        let discoveredID = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        store.selectDevice(
            ProximityDeviceSelection(id: selectedID, reportedName: "我的手机")
        )
        bluetooth.send(
            .devices([ProximityDevice(id: discoveredID, name: "附近设备", rssi: -50)])
        )
        store.beginDeviceSelection()
        defer { store.endDeviceSelection() }

        let selected = try #require(store.devicePickerEntries.first)
        #expect(store.devicePickerEntries.map(\.id) == [selectedID, discoveredID])
        #expect(selected.displayName == "我的手机")
        #expect(selected.signal(at: Date(), bluetoothPoweredOn: true) == .unavailable)
    }

    @Test @MainActor func settingsWindowKeepsMigratedLayoutSize() {
        #expect(SettingsView.windowSize == CGSize(width: 860, height: 620))
    }

    @Test @MainActor func devicePickerKeepsConfiguredLayoutSize() {
        #expect(ProximityDevicePickerSheet.windowSize == CGSize(width: 500, height: 420))
    }

    @Test func automaticUnlockRequiresSelectedDevice() {
        var configuration = ProximityConfiguration.default
        configuration.selectedDeviceID = UUID()

        #expect(
            ProximityAutomaticUnlockPolicy.shouldAttempt(
                configuration: configuration,
                manualLock: false,
                isPresent: true,
                systemSleeping: false,
                displaySleeping: false
            )
        )

        configuration.selectedDeviceID = nil

        #expect(!ProximityAutomaticUnlockPolicy.isEnabled(configuration: configuration))
        #expect(
            !ProximityAutomaticUnlockPolicy.shouldAttempt(
                configuration: configuration,
                manualLock: false,
                isPresent: true,
                systemSleeping: false,
                displaySleeping: false
            )
        )
    }

    @Test @MainActor func stoppingMonitoringClearsDeviceAndPresenceState() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-stop-monitoring-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let id = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        store.selectDevice(
            ProximityDeviceSelection(id: id, reportedName: "我的手机")
        )
        bluetooth.send(.signal(rssi: -48, active: true))

        store.stopMonitoring()

        #expect(store.configuration.selectedDeviceID == nil)
        #expect(store.selectedDeviceName == nil)
        #expect(store.latestRSSI == nil)
        #expect(!store.isPresent)
        #expect(bluetooth.monitoredDeviceID == nil)
        #expect(bluetooth.monitoringRequests == [nil, id, nil])
    }

    @Test @MainActor func selectingUnavailableDevicePreservesItsOwnName() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-offline-selection-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstID = UUID()
        let secondID = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        store.selectDevice(
            ProximityDeviceSelection(id: firstID, reportedName: "旧设备")
        )
        store.beginDeviceSelection()
        defer { store.endDeviceSelection() }
        bluetooth.send(
            .devices([ProximityDevice(id: secondID, name: "新设备", rssi: -55)])
        )
        bluetooth.send(.devices([]))
        let unavailable = try #require(
            store.devicePickerEntries.first { $0.id == secondID }
        )

        store.selectDevice(unavailable.selection)

        #expect(store.configuration.selectedDeviceID == secondID)
        #expect(store.selectedDeviceName == "新设备")
    }

    @Test @MainActor func restartingDiscoveryClearsResultsAndRestartsController() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-restart-picker-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        store.start()
        store.beginDeviceSelection()
        defer { store.endDeviceSelection() }
        bluetooth.send(
            .devices([ProximityDevice(id: UUID(), name: "附近设备", rssi: -45)])
        )

        store.restartDeviceDiscovery()

        #expect(store.devicePickerEntries.isEmpty)
        #expect(bluetooth.restartScanningRequests == 1)
    }

    @Test @MainActor func devicePickerMarksStaleOrPoweredOffSignalUnavailable() {
        let lastSeenAt = Date(timeIntervalSince1970: 1_000)
        let entry = ProximityDevicePickerEntry(
            selection: ProximityDeviceSelection(id: UUID(), reportedName: "手机"),
            displayName: "手机",
            rssi: -50,
            lastSeenAt: lastSeenAt
        )

        #expect(
            entry.signal(
                at: lastSeenAt.addingTimeInterval(5),
                bluetoothPoweredOn: true
            ) == .good
        )
        #expect(
            entry.signal(
                at: lastSeenAt.addingTimeInterval(11),
                bluetoothPoweredOn: true
            ) == .unavailable
        )
        #expect(
            entry.signal(at: lastSeenAt, bluetoothPoweredOn: false) == .unavailable
        )
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

    @Test @MainActor func deviceAliasOverridesAndPersistsDiscoveredName() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-alias-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let id = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        let device = ProximityDevice(
            id: id,
            name: "iPhone 13 Pro",
            rssi: -48
        )
        store.start()
        bluetooth.send(.devices([device]))
        store.selectDevice(
            ProximityDeviceSelection(id: id, reportedName: device.name)
        )

        store.renameSelectedDevice(to: "  我的手机  ")

        #expect(store.selectedDeviceName == "我的手机")
        #expect(store.displayName(for: device) == "我的手机")

        let restoredStore = ProximityLockStore(
            defaults: defaults,
            bluetoothController: FakeBluetoothController(),
            systemController: FakeProximitySystemController()
        )
        #expect(restoredStore.selectedDeviceName == "我的手机")
    }

    @Test @MainActor func clearingAliasForOfflineDeviceRestoresReportedName() throws {
        let suiteName = "com.perryfinn.random-thoughts.proximity-clear-alias-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let id = UUID()
        let bluetooth = FakeBluetoothController()
        let store = ProximityLockStore(
            defaults: defaults,
            bluetoothController: bluetooth,
            systemController: FakeProximitySystemController()
        )
        let device = ProximityDevice(id: id, name: "iPhone 13 Pro", rssi: -48)
        store.start()
        bluetooth.send(.devices([device]))
        store.selectDevice(
            ProximityDeviceSelection(id: id, reportedName: device.name)
        )
        store.renameSelectedDevice(to: "我的手机")
        bluetooth.send(.devices([]))

        store.renameSelectedDevice(to: "   ")

        #expect(store.selectedDeviceName == "iPhone 13 Pro")

        let restoredStore = ProximityLockStore(
            defaults: defaults,
            bluetoothController: FakeBluetoothController(),
            systemController: FakeProximitySystemController()
        )
        #expect(restoredStore.selectedDeviceName == "iPhone 13 Pro")
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
        await waitUntil(timeout: .seconds(2)) {
            !system.enteredPasswords.isEmpty
        }

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
private func waitUntil(
    timeout: Duration,
    condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private final class FakeBluetoothController: ProximityBluetoothControlling {
    var eventHandler: ((ProximityBluetoothEvent) -> Void)?
    var configuration = ProximityConfiguration.default
    var monitoredDeviceID: UUID?
    var monitoringRequests: [UUID?] = []
    var restartScanningRequests = 0

    func apply(configuration: ProximityConfiguration) {
        self.configuration = configuration
    }

    func startMonitoring(deviceID: UUID?) {
        monitoredDeviceID = deviceID
        monitoringRequests.append(deviceID)
    }

    func startScanning() {}
    func restartScanning() { restartScanningRequests += 1 }
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
