@preconcurrency import CoreBluetooth
import Foundation
import OSLog

@MainActor
protocol ProximityBluetoothControlling: AnyObject {
    var eventHandler: ((ProximityBluetoothEvent) -> Void)? { get set }

    func apply(configuration: ProximityConfiguration)
    func startMonitoring(deviceID: UUID?)
    func startScanning()
    func stopScanning()
}

@MainActor
final class ProximityBluetoothController: NSObject, ProximityBluetoothControlling {
    var eventHandler: ((ProximityBluetoothEvent) -> Void)?

    private static let deviceInformation = CBUUID(string: "180A")
    private static let manufacturerName = CBUUID(string: "2A29")
    private static let modelName = CBUUID(string: "2A24")
    private static let exposureNotification = CBUUID(string: "FD6F")

    private var centralManager: CBCentralManager!
    private var configuration: ProximityConfiguration
    private var discoveredDevices: [UUID: InternalDevice] = [:]
    private var monitoredPeripheral: CBPeripheral?
    private var detector = ProximityPresenceDetector()
    private var scanMode = false
    private var activeModeTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var lastActiveReadAt: Date?

    init(configuration: ProximityConfiguration) {
        self.configuration = configuration
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        maintenanceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.performMaintenance()
            }
        }
    }

    deinit {
        maintenanceTask?.cancel()
        activeModeTask?.cancel()
        connectionTask?.cancel()
    }

    func apply(configuration: ProximityConfiguration) {
        let passiveModeChanged = self.configuration.passiveMode != configuration.passiveMode
        self.configuration = configuration

        if passiveModeChanged, configuration.passiveMode {
            leaveActiveMode()
            if let monitoredPeripheral {
                centralManager.cancelPeripheralConnection(monitoredPeripheral)
            }
        }
        reconcileScanning()
    }

    func startMonitoring(deviceID: UUID?) {
        if let monitoredPeripheral {
            centralManager.cancelPeripheralConnection(monitoredPeripheral)
        }

        monitoredPeripheral = nil
        leaveActiveMode()
        detector.reset(at: Date(), present: true)
        configuration.selectedDeviceID = deviceID

        guard deviceID != nil else {
            eventHandler?(.signal(rssi: nil, active: false))
            reconcileScanning()
            return
        }

        reconcileScanning()
    }

    func startScanning() {
        scanMode = true
        reconcileScanning()
        publishDevices()
    }

    func stopScanning() {
        scanMode = false
        reconcileScanning()
    }

    private func scanForPeripherals() {
        guard centralManager.state == .poweredOn,
              !centralManager.isScanning else {
            return
        }

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        AppTelemetry.proximity.debug("Bluetooth scan started")
    }

    private func reconcileScanning() {
        guard centralManager.state == .poweredOn else { return }

        let shouldScan = ProximityBluetoothScanPolicy.shouldScan(
            isDeviceDiscoveryRequested: scanMode,
            hasSelectedDevice: configuration.selectedDeviceID != nil,
            isActivelyReadingRSSI: activeModeTask != nil
        )
        if shouldScan {
            scanForPeripherals()
        } else if centralManager.isScanning {
            centralManager.stopScan()
            AppTelemetry.proximity.debug("Bluetooth scan stopped")
        }
    }

    private func performMaintenance() {
        let now = Date()
        if configuration.selectedDeviceID != nil,
           centralManager.state == .poweredOn {
            let result = detector.tick(at: now, configuration: configuration)
            if result.signalWasLost {
                eventHandler?(.signal(rssi: nil, active: false))
            }
            if let transition = result.transition {
                eventHandler?(
                    .presence(isPresent: detector.isPresent, reason: transition)
                )
            }
        }

        let expiredIDs = discoveredDevices.compactMap { id, device in
            now.timeIntervalSince(device.lastSeenAt) >= configuration.signalTimeout ? id : nil
        }
        guard !expiredIDs.isEmpty else { return }
        for id in expiredIDs {
            if let peripheral = discoveredDevices[id]?.peripheral,
               peripheral !== monitoredPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            discoveredDevices.removeValue(forKey: id)
        }
        publishDevices()
    }

    private func updateMonitoredPeripheral(rssi: Int) {
        let result = detector.receive(
            rssi: rssi,
            at: Date(),
            configuration: configuration
        )
        eventHandler?(
            .signal(rssi: result.estimatedRSSI, active: activeModeTask != nil)
        )
        if let transition = result.transition {
            eventHandler?(
                .presence(isPresent: detector.isPresent, reason: transition)
            )
        }
    }

    private func connectMonitoredPeripheral() {
        guard let monitoredPeripheral else { return }

        // BLEUnlock intentionally performs this read before the connection callback;
        // some Apple devices respond more reliably through this path.
        monitoredPeripheral.readRSSI()
        guard monitoredPeripheral.state == .disconnected else { return }

        centralManager.connect(monitoredPeripheral, options: nil)
        connectionTask?.cancel()
        connectionTask = Task { @MainActor [weak self, weak monitoredPeripheral] in
            try? await Task.sleep(for: .seconds(60))
            guard let self,
                  let monitoredPeripheral,
                  !Task.isCancelled,
                  monitoredPeripheral.state == .connecting else {
                return
            }
            self.centralManager.cancelPeripheralConnection(monitoredPeripheral)
        }
    }

    private func enterActiveMode(for peripheral: CBPeripheral) {
        guard activeModeTask == nil, !configuration.passiveMode else { return }

        if !scanMode, centralManager.state == .poweredOn {
            centralManager.stopScan()
        }
        activeModeTask = Task { @MainActor [weak self, weak peripheral] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self,
                      let peripheral,
                      !Task.isCancelled else {
                    return
                }

                if let lastActiveReadAt = self.lastActiveReadAt,
                   Date().timeIntervalSince(lastActiveReadAt) > 10 {
                    self.centralManager.cancelPeripheralConnection(peripheral)
                    self.leaveActiveMode()
                    self.reconcileScanning()
                    return
                } else if peripheral.state == .connected {
                    peripheral.readRSSI()
                } else {
                    self.connectMonitoredPeripheral()
                }
            }
        }
        reconcileScanning()
        AppTelemetry.proximity.info("Bluetooth monitor entered active mode")
    }

    private func leaveActiveMode() {
        activeModeTask?.cancel()
        activeModeTask = nil
        lastActiveReadAt = nil
    }

    private func publishDevices() {
        let devices = discoveredDevices.values
            .map(\.snapshot)
            .sorted { lhs, rhs in
                if lhs.rssi == rhs.rssi {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.rssi > rhs.rssi
            }
        eventHandler?(.devices(devices))
    }

    private func device(
        for peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: Int
    ) -> InternalDevice {
        if let existing = discoveredDevices[peripheral.identifier] {
            existing.peripheral = peripheral
            existing.rssi = rssi
            existing.lastSeenAt = Date()
            if let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                existing.advertisedName = advertisedName
            }
            if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                existing.advertisementData = data
            }
            return existing
        }

        let device = InternalDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            rssi: rssi,
            advertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            advertisementData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        )
        discoveredDevices[peripheral.identifier] = device
        return device
    }
}

extension ProximityBluetoothController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: ProximityBluetoothState
        switch central.state {
        case .unknown: state = .unknown
        case .resetting: state = .resetting
        case .unsupported: state = .unsupported
        case .unauthorized: state = .unauthorized
        case .poweredOff: state = .poweredOff
        case .poweredOn: state = .poweredOn
        @unknown default: state = .unknown
        }
        eventHandler?(.state(state))

        if central.state == .poweredOn {
            reconcileScanning()
        } else {
            leaveActiveMode()
            detector.reset(at: Date(), present: false)
            eventHandler?(.signal(rssi: nil, active: false))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue

        if peripheral.identifier == configuration.selectedDeviceID {
            monitoredPeripheral = peripheral
            if activeModeTask == nil {
                updateMonitoredPeripheral(rssi: rssi)
                if !configuration.passiveMode {
                    connectMonitoredPeripheral()
                }
            }
        }

        guard scanMode else { return }
        if let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           advertisedServices.contains(Self.exposureNotification) {
            return
        }

        if discoveredDevices[peripheral.identifier] == nil,
           rssi < configuration.minimumScanRSSI {
            return
        }

        _ = device(
            for: peripheral,
            advertisementData: advertisementData,
            rssi: rssi
        )
        publishDevices()

        if peripheral.state == .disconnected {
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        if scanMode {
            peripheral.discoverServices([Self.deviceInformation])
        }
        if peripheral === monitoredPeripheral, !configuration.passiveMode {
            connectionTask?.cancel()
            connectionTask = nil
            peripheral.readRSSI()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        if peripheral === monitoredPeripheral {
            leaveActiveMode()
            reconcileScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if peripheral === monitoredPeripheral {
            leaveActiveMode()
            reconcileScanning()
        }
    }
}

extension ProximityBluetoothController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral === monitoredPeripheral else { return }
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        updateMonitoredPeripheral(rssi: rssi)
        lastActiveReadAt = Date()
        enterActiveMode(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.deviceInformation {
            peripheral.discoverCharacteristics(
                [Self.manufacturerName, Self.modelName],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? []
        where characteristic.uuid == Self.manufacturerName
            || characteristic.uuid == Self.modelName {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let value = characteristic.value,
              let text = String(data: value, encoding: .utf8),
              let device = discoveredDevices[peripheral.identifier] else {
            return
        }

        if characteristic.uuid == Self.manufacturerName {
            device.manufacturer = text
        } else if characteristic.uuid == Self.modelName {
            device.model = text
        }
        publishDevices()

        if device.manufacturer != nil,
           device.model != nil,
           peripheral !== monitoredPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices([Self.deviceInformation])
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        guard discoveredDevices[peripheral.identifier] != nil else { return }
        publishDevices()
    }
}

@MainActor
private final class InternalDevice {
    let id: UUID
    var peripheral: CBPeripheral
    var rssi: Int
    var advertisedName: String?
    var advertisementData: Data?
    var manufacturer: String?
    var model: String?
    var lastSeenAt = Date()

    init(
        id: UUID,
        peripheral: CBPeripheral,
        rssi: Int,
        advertisedName: String?,
        advertisementData: Data?
    ) {
        self.id = id
        self.peripheral = peripheral
        self.rssi = rssi
        self.advertisedName = advertisedName
        self.advertisementData = advertisementData
    }

    var snapshot: ProximityDevice {
        ProximityDevice(
            id: id,
            name: displayName,
            rssi: rssi
        )
    }

    private var displayName: String {
        ProximityDeviceNameResolver.resolve(
            id: id,
            advertisedName: advertisedName,
            peripheralName: peripheral.name,
            manufacturer: manufacturer,
            model: model,
            beaconDescription: beaconDescription
        )
    }

    private var beaconDescription: String? {
        guard let advertisementData,
              advertisementData.count >= 25,
              advertisementData.prefix(4) == Data([0x4c, 0x00, 0x02, 0x15]) else {
            return nil
        }

        let major = UInt16(advertisementData[20]) << 8 | UInt16(advertisementData[21])
        let minor = UInt16(advertisementData[22]) << 8 | UInt16(advertisementData[23])
        let transmittedPower = Int(Int8(bitPattern: advertisementData[24]))
        let distance = pow(10, Double(transmittedPower - rssi) / 20)
        return String(format: "iBeacon [%d, %d] %.1fm", major, minor, distance)
    }
}
