import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ProximityLockStore {
    static let minimumRSSI = -100
    static let maximumRSSI = -30
    static let rssiValues = Array(stride(from: maximumRSSI, through: minimumRSSI, by: -5))
    static let minimumScanRSSIRange = -127...0
    static let lockDelayValues: [TimeInterval] = [2, 5, 15, 30, 60, 120, 300]
    static let signalTimeoutValues: [TimeInterval] = [30, 60, 120, 300, 600]

    private(set) var configuration: ProximityConfiguration
    private(set) var devices: [ProximityDevice] = []
    private(set) var bluetoothState: ProximityBluetoothState = .unknown
    private(set) var latestRSSI: Int?
    private(set) var signalIsActive = false
    private(set) var isPresent = true
    private(set) var isScanning = false
    private(set) var hasPassword = false
    private(set) var accessibilityTrusted = false
    private(set) var launchAtLoginRequested = false
    private(set) var lastError: String?
    private var deviceAliases: [String: String]
    private var devicePickerState = ProximityDevicePickerState()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let systemController: ProximitySystemControlling
    @ObservationIgnored private var bluetoothController: ProximityBluetoothControlling?
    @ObservationIgnored private var eventMonitor: ProximitySystemEventMonitor?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var unlockTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var displaySleeping = false
    @ObservationIgnored private var systemSleeping = false
    @ObservationIgnored private var inScreensaver = false
    @ObservationIgnored private var manualLock = false
    @ObservationIgnored private var nowPlayingWasPlaying = false
    @ObservationIgnored private var unlockedAt = Date.distantPast

    private enum Keys {
        static let configuration = "proximity.configuration.v1"
        static let selectedDeviceReportedName = "proximity.selected-device-name"
        static let deviceAliases = "proximity.device-aliases.v1"
        static let lastUpdateCheck = "proximity.last-update-check"
    }

    init(
        defaults: UserDefaults = .standard,
        bluetoothController: ProximityBluetoothControlling? = nil,
        systemController: ProximitySystemControlling? = nil
    ) {
        self.defaults = defaults
        self.bluetoothController = bluetoothController
        self.systemController = systemController ?? ProximitySystemController()
        deviceAliases = defaults.dictionary(forKey: Keys.deviceAliases) as? [String: String] ?? [:]

        if let data = defaults.data(forKey: Keys.configuration),
           let saved = try? JSONDecoder().decode(ProximityConfiguration.self, from: data) {
            configuration = Self.normalized(saved)
        } else {
            configuration = .default
        }

        refreshSecurityState()
    }

    var selectedDevice: ProximityDevice? {
        guard let selectedDeviceID = configuration.selectedDeviceID else { return nil }
        return devices.first { $0.id == selectedDeviceID }
    }

    var selectedDeviceName: String? {
        guard let selectedDeviceID = configuration.selectedDeviceID else { return nil }
        return deviceAlias(for: selectedDeviceID)
            ?? selectedDeviceReportedName
    }

    var devicePickerEntries: [ProximityDevicePickerEntry] {
        devicePickerState.entries
    }

    func displayName(for device: ProximityDevice) -> String {
        deviceAlias(for: device.id) ?? device.name
    }

    var availableUnlockRSSIValues: [Int] {
        Self.rssiValues.filter {
            guard let lockRSSI = configuration.lockRSSI else { return true }
            return $0 >= lockRSSI
        }
    }

    var availableLockRSSIValues: [Int] {
        Self.rssiValues.filter {
            guard let unlockRSSI = configuration.unlockRSSI else { return true }
            return $0 <= unlockRSSI
        }
    }

    var statusText: String {
        guard configuration.selectedDeviceID != nil else {
            return "尚未选择设备"
        }
        switch bluetoothState {
        case .poweredOff:
            return "蓝牙已关闭"
        case .unauthorized:
            return "未获得蓝牙权限"
        case .unsupported:
            return "这台 Mac 不支持蓝牙低功耗"
        case .resetting:
            return "蓝牙正在重置"
        case .unknown:
            return "正在初始化蓝牙"
        case .poweredOn:
            if let latestRSSI {
                return "\(latestRSSI) dBm\(signalIsActive ? " · 主动" : "")"
            }
            return "未检测到信号"
        }
    }

    var statusSystemImage: String {
        if bluetoothState == .poweredOff || bluetoothState == .unauthorized {
            return "bluetooth.slash"
        }
        if latestRSSI != nil {
            return "lock.open.display"
        }
        return "lock.display"
    }

    var scriptPath: String {
        systemController.applicationScriptURL?.path ?? "无法确定脚本目录"
    }

    func start() {
        guard !started else { return }
        started = true

        let bluetooth = bluetoothController
            ?? ProximityBluetoothController(configuration: configuration)
        bluetoothController = bluetooth
        bluetooth.eventHandler = { [weak self] event in
            self?.handleBluetoothEvent(event)
        }
        bluetooth.apply(configuration: configuration)
        bluetooth.startMonitoring(deviceID: configuration.selectedDeviceID)

        let eventMonitor = ProximitySystemEventMonitor()
        eventMonitor.handler = { [weak self] event in
            self?.handleSystemEvent(event)
        }
        self.eventMonitor = eventMonitor

        if configuration.selectedDeviceID != nil,
           configuration.lockRSSI != nil {
            systemController.requestNotificationAuthorization()
        }
        refreshSecurityState()
        checkForUpdatesIfNeeded()

        if configuration.selectedDeviceID != nil,
           configuration.unlockRSSI != nil,
           !hasPassword {
            promptForPassword()
        }

        AppTelemetry.proximity.info("Proximity lock module started")
    }

    func updateConfiguration(_ newValue: ProximityConfiguration) {
        let oldConfiguration = configuration
        let oldDeviceID = configuration.selectedDeviceID
        configuration = Self.normalized(newValue)
        saveConfiguration()
        bluetoothController?.apply(configuration: configuration)

        if oldDeviceID != configuration.selectedDeviceID {
            cancelPendingUnlock()
            bluetoothController?.startMonitoring(deviceID: configuration.selectedDeviceID)
            latestRSSI = nil
            signalIsActive = false
            isPresent = configuration.selectedDeviceID != nil
            if configuration.selectedDeviceID == nil {
                wakeTask?.cancel()
                wakeTask = nil
            }
        }
        if configuration.unlockRSSI == nil {
            cancelPendingUnlock()
        }
        if configuration.selectedDeviceID != nil,
           configuration.lockRSSI != nil,
           (oldConfiguration.selectedDeviceID == nil || oldConfiguration.lockRSSI == nil) {
            systemController.requestNotificationAuthorization()
        }
        refreshSecurityState()
    }

    func setConfigurationValue<Value>(
        _ keyPath: WritableKeyPath<ProximityConfiguration, Value>,
        to value: Value
    ) {
        var updated = configuration
        updated[keyPath: keyPath] = value
        updateConfiguration(updated)
    }

    func selectDevice(_ selection: ProximityDeviceSelection) {
        var updated = configuration
        updated.selectedDeviceID = selection.id
        defaults.set(selection.reportedName, forKey: Keys.selectedDeviceReportedName)
        updateConfiguration(updated)

        if configuration.unlockRSSI != nil, !hasPassword {
            promptForPassword()
        }
    }

    func stopMonitoring() {
        var updated = configuration
        updated.selectedDeviceID = nil
        defaults.removeObject(forKey: Keys.selectedDeviceReportedName)
        updateConfiguration(updated)
    }

    func renameSelectedDevice(to name: String) {
        guard let deviceID = configuration.selectedDeviceID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deviceAliases.removeValue(forKey: deviceID.uuidString)
        } else {
            deviceAliases[deviceID.uuidString] = trimmed
        }
        defaults.set(deviceAliases, forKey: Keys.deviceAliases)
    }

    func beginDeviceSelection() {
        devicePickerState.reset(
            currentDevices: devices.map(makeDevicePickerEntry),
            selectedDevice: selectedDevicePickerEntry
        )
        isScanning = true
        bluetoothController?.startScanning()
    }

    func restartDeviceDiscovery() {
        devicePickerState.reset(
            currentDevices: [],
            selectedDevice: selectedDevicePickerEntry
        )
        isScanning = true
        bluetoothController?.restartScanning()
    }

    func endDeviceSelection() {
        isScanning = false
        bluetoothController?.stopScanning()
    }

    func lockNow() {
        guard !systemController.isScreenLocked else { return }
        cancelPendingUnlock()
        manualLock = true
        pauseNowPlayingIfNeeded()
        performLock(reason: nil)
    }

    func promptForPassword() {
        guard let password = systemController.promptForPassword() else { return }
        setPassword(password)
    }

    func setPassword(_ password: String) {
        guard !password.isEmpty else { return }
        do {
            try systemController.storePassword(password)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshSecurityState()
    }

    func deletePassword() {
        do {
            try systemController.deletePassword()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshSecurityState()
    }

    func requestAccessibilityPermission() {
        systemController.requestAccessibilityPermission()
        refreshSecurityState()
    }

    func refreshSystemState() {
        refreshSecurityState()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try systemController.setLaunchAtLogin(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshSecurityState()
    }

    func openApplicationScriptsFolder() {
        systemController.openApplicationScriptsFolder()
    }

    func clearError() {
        lastError = nil
    }

    private func handleBluetoothEvent(_ event: ProximityBluetoothEvent) {
        switch event {
        case .state(let state):
            let previousState = bluetoothState
            bluetoothState = state
            if state == .poweredOff, previousState != .poweredOff {
                systemController.presentBluetoothPowerWarning()
            } else if state == .unauthorized {
                lastError = "随想没有蓝牙访问权限，请在系统设置的隐私与安全性中允许访问。"
            }

        case .devices(let devices):
            self.devices = devices
            if let selectedDevice {
                defaults.set(selectedDevice.name, forKey: Keys.selectedDeviceReportedName)
            }
            if isScanning {
                devicePickerState.merge(
                    currentDevices: devices.map(makeDevicePickerEntry),
                    selectedDevice: selectedDevicePickerEntry
                )
            }

        case .signal(let rssi, let active):
            latestRSSI = rssi
            signalIsActive = active

        case .presence(let present, let reason):
            isPresent = present
            handlePresence(present: present, reason: reason)
        }
    }

    private func deviceAlias(for id: UUID) -> String? {
        deviceAliases[id.uuidString]
    }

    private var selectedDeviceReportedName: String? {
        selectedDevice?.name
            ?? defaults.string(forKey: Keys.selectedDeviceReportedName)
    }

    private var selectedDevicePickerEntry: ProximityDevicePickerEntry? {
        guard let id = configuration.selectedDeviceID,
              let reportedName = selectedDeviceReportedName else {
            return nil
        }
        if let selectedDevice {
            return makeDevicePickerEntry(selectedDevice)
        }
        return ProximityDevicePickerEntry(
            selection: ProximityDeviceSelection(id: id, reportedName: reportedName),
            displayName: deviceAlias(for: id) ?? reportedName,
            rssi: nil,
            lastSeenAt: nil
        )
    }

    private func makeDevicePickerEntry(
        _ device: ProximityDevice
    ) -> ProximityDevicePickerEntry {
        ProximityDevicePickerEntry(
            selection: ProximityDeviceSelection(id: device.id, reportedName: device.name),
            displayName: displayName(for: device),
            rssi: device.rssi,
            lastSeenAt: device.lastSeenAt
        )
    }

    private func handlePresence(
        present: Bool,
        reason: ProximityPresenceReason
    ) {
        guard configuration.selectedDeviceID != nil,
              bluetoothState == .poweredOn else {
            return
        }

        if present {
            guard configuration.unlockRSSI != nil else { return }
            systemController.removeLockNotification()

            if displaySleeping,
               !systemSleeping,
               configuration.wakeOnProximity {
                systemController.wakeDisplay()
                startWakeRetryTimer()
            }
            tryUnlockScreen()
            return
        }

        cancelPendingUnlock()
        if !systemController.isScreenLocked, configuration.lockRSSI != nil {
            pauseNowPlayingIfNeeded()
            performLock(reason: reason)
        }
        manualLock = false
    }

    private func performLock(reason: ProximityPresenceReason?) {
        do {
            try systemController.lockScreen(
                useScreensaver: configuration.useScreensaverToLock,
                turnOffDisplay: configuration.turnOffDisplayOnLock
            )
            lastError = nil
            if let reason {
                systemController.notifyLocked(reason: reason)
                systemController.runEventScript(
                    argument: reason.rawValue,
                    rssi: latestRSSI
                )
            }
            AppTelemetry.proximity.info("Screen lock requested")
        } catch {
            lastError = error.localizedDescription
            AppTelemetry.proximity.error("Screen lock failed")
        }
    }

    private func tryUnlockScreen() {
        guard canAttemptAutomaticUnlock else {
            return
        }

        if inScreensaver {
            systemController.sendEscapeKey()
        }
        guard !configuration.wakeWithoutUnlocking else { return }

        unlockTask?.cancel()
        unlockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self,
                  !Task.isCancelled,
                  self.canAttemptAutomaticUnlock,
                  self.systemController.isScreenLocked else {
                return
            }

            guard self.systemController.isAccessibilityTrusted else {
                self.accessibilityTrusted = false
                self.lastError = "尚未获得辅助功能权限，无法自动输入登录密码。"
                return
            }

            do {
                guard let password = try self.systemController.fetchPassword() else {
                    self.lastError = "尚未设置 macOS 登录密码，无法自动解锁。"
                    return
                }
                guard !Task.isCancelled,
                      self.canAttemptAutomaticUnlock,
                      self.systemController.isScreenLocked,
                      self.systemController.isAccessibilityTrusted else {
                    return
                }
                self.unlockedAt = Date()
                self.systemController.enterPassword(password)
                self.resumeNowPlayingIfNeeded()
                self.systemController.runEventScript(
                    argument: "unlocked",
                    rssi: self.latestRSSI
                )
                AppTelemetry.proximity.info("Unlock keystrokes posted")
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func pauseNowPlayingIfNeeded() {
        guard configuration.pauseNowPlaying else { return }
        systemController.pauseNowPlaying { [weak self] wasPlaying in
            self?.nowPlayingWasPlaying = wasPlaying
        }
    }

    private func resumeNowPlayingIfNeeded() {
        guard configuration.pauseNowPlaying, nowPlayingWasPlaying else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.systemController.resumeNowPlaying()
            self.nowPlayingWasPlaying = false
        }
    }

    private func handleSystemEvent(_ event: ProximitySystemEvent) {
        switch event {
        case .displaySleep:
            cancelPendingUnlock()
            displaySleeping = true

        case .displayWake:
            displaySleeping = false
            wakeTask?.cancel()
            wakeTask = nil
            tryUnlockScreen()

        case .systemSleep:
            cancelPendingUnlock()
            systemSleeping = true
            NSApplication.shared.setActivationPolicy(.regular)

        case .systemWake:
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                NSApplication.shared.setActivationPolicy(.accessory)
                self.systemSleeping = false
                self.tryUnlockScreen()
            }

        case .screenUnlocked:
            handleScreenUnlocked()

        case .screensaverStarted:
            inScreensaver = true

        case .screensaverStopped:
            inScreensaver = false
        }
    }

    private func handleScreenUnlocked() {
        cancelPendingUnlock()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            let actions = ProximityScreenUnlockPolicy.actions(
                elapsedSinceAutomaticUnlock: Date().timeIntervalSince(self.unlockedAt),
                automaticUnlockEnabled: ProximityAutomaticUnlockPolicy.isEnabled(
                    configuration: self.configuration
                )
            )
            if actions.shouldRunIntrudedScript {
                self.systemController.runEventScript(
                    argument: "intruded",
                    rssi: self.latestRSSI
                )
            }
            if actions.shouldResumePlayback {
                self.resumeNowPlayingIfNeeded()
            }
        }
        manualLock = false
        checkForUpdatesIfNeeded()
    }

    private func startWakeRetryTimer() {
        wakeTask?.cancel()
        wakeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.systemController.wakeDisplay()
            }
        }
    }

    private var canAttemptAutomaticUnlock: Bool {
        ProximityAutomaticUnlockPolicy.shouldAttempt(
            configuration: configuration,
            manualLock: manualLock,
            isPresent: isPresent,
            systemSleeping: systemSleeping,
            displaySleeping: displaySleeping
        )
    }

    private func cancelPendingUnlock() {
        unlockTask?.cancel()
        unlockTask = nil
    }

    private func refreshSecurityState() {
        hasPassword = systemController.containsPassword
        accessibilityTrusted = systemController.isAccessibilityTrusted
        launchAtLoginRequested = systemController.isLaunchAtLoginRequested
    }

    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Keys.configuration)
        }
    }

    private func checkForUpdatesIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        guard updateTask == nil else { return }
        let now = Date()
        if let lastCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date,
           now.timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }

        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { self.updateTask = nil }
            let checker = ReleaseUpdateChecker()
            guard let latestVersion = await checker.latestVersion() else {
                return
            }
            self.defaults.set(Date(), forKey: Keys.lastUpdateCheck)

            guard let currentVersion = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                  ) as? String,
                  ReleaseUpdateChecker.isNewerVersion(
                    latestVersion,
                    than: currentVersion
                  ) else {
                return
            }
            self.systemController.notifyUpdateAvailable(
                version: latestVersion,
                releasesURL: checker.releasesURL
            )
        }
    }

    private static func normalized(
        _ configuration: ProximityConfiguration
    ) -> ProximityConfiguration {
        var result = configuration
        result.lockRSSI = result.lockRSSI.map {
            min(max($0, minimumRSSI), maximumRSSI)
        }
        result.unlockRSSI = result.unlockRSSI.map {
            min(max($0, minimumRSSI), maximumRSSI)
        }
        if let lockRSSI = result.lockRSSI,
           let unlockRSSI = result.unlockRSSI,
           lockRSSI > unlockRSSI {
            result.lockRSSI = unlockRSSI
        }
        result.minimumScanRSSI = min(
            max(result.minimumScanRSSI, minimumScanRSSIRange.lowerBound),
            minimumScanRSSIRange.upperBound
        )
        result.lockDelay = max(1, result.lockDelay)
        result.signalTimeout = max(5, result.signalTimeout)
        return result
    }
}
