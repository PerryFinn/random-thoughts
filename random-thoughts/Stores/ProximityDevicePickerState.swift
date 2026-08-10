import Foundation

struct ProximityDeviceSelection: Equatable, Sendable {
    let id: UUID
    let reportedName: String
}

enum ProximityDeviceSignal: Equatable, Sendable {
    case good
    case fair
    case weak
    case unavailable

    var description: String {
        switch self {
        case .good: "信号良好"
        case .fair: "信号一般"
        case .weak: "信号较弱"
        case .unavailable: "暂时无信号"
        }
    }

    var isAvailable: Bool {
        self != .unavailable
    }
}

struct ProximityDevicePickerEntry: Identifiable, Equatable, Sendable {
    static let signalFreshnessInterval: TimeInterval = 10

    var selection: ProximityDeviceSelection
    var displayName: String
    var rssi: Int?
    var lastSeenAt: Date?

    var id: UUID { selection.id }

    func signal(at date: Date, bluetoothPoweredOn: Bool) -> ProximityDeviceSignal {
        guard bluetoothPoweredOn,
              let rssi,
              let lastSeenAt,
              date.timeIntervalSince(lastSeenAt) <= Self.signalFreshnessInterval else {
            return .unavailable
        }
        if rssi >= -55 { return .good }
        if rssi >= -70 { return .fair }
        return .weak
    }
}

struct ProximityDevicePickerState: Equatable, Sendable {
    private(set) var entries: [ProximityDevicePickerEntry] = []

    mutating func reset(
        currentDevices: [ProximityDevicePickerEntry],
        selectedDevice: ProximityDevicePickerEntry?
    ) {
        entries.removeAll(keepingCapacity: true)
        merge(currentDevices: currentDevices, selectedDevice: selectedDevice)
    }

    mutating func merge(
        currentDevices: [ProximityDevicePickerEntry],
        selectedDevice: ProximityDevicePickerEntry?
    ) {
        let currentByID = Dictionary(
            uniqueKeysWithValues: currentDevices.map { ($0.id, $0) }
        )

        for index in entries.indices {
            let id = entries[index].id
            if let current = currentByID[id] {
                entries[index] = current
            } else {
                entries[index].rssi = nil
                entries[index].lastSeenAt = nil
                if id == selectedDevice?.id, let selectedDevice {
                    entries[index].selection = selectedDevice.selection
                    entries[index].displayName = selectedDevice.displayName
                }
            }
        }

        if let selectedDevice,
           !entries.contains(where: { $0.id == selectedDevice.id }) {
            entries.insert(selectedDevice, at: 0)
        }

        var knownIDs = Set(entries.map(\.id))
        for device in currentDevices where !knownIDs.contains(device.id) {
            entries.append(device)
            knownIDs.insert(device.id)
        }

        guard let selectedID = selectedDevice?.id,
              let selectedIndex = entries.firstIndex(where: { $0.id == selectedID }),
              selectedIndex != entries.startIndex else {
            return
        }
        let entry = entries.remove(at: selectedIndex)
        entries.insert(entry, at: 0)
    }
}
