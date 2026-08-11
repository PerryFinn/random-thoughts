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

    fileprivate var duplicateKey: String {
        selection.reportedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

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

struct ProximityDevicePickerSearch: Equatable, Sendable {
    let query: String

    init(_ text: String) {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func filter(
        _ entries: [ProximityDevicePickerEntry]
    ) -> [ProximityDevicePickerEntry] {
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.displayName.localizedStandardContains(query)
                || entry.selection.reportedName.localizedStandardContains(query)
                || entry.id.uuidString.localizedStandardContains(query)
        }
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
        var preferredIDByKey: [String: UUID] = [:]
        for entry in entries where preferredIDByKey[entry.duplicateKey] == nil {
            preferredIDByKey[entry.duplicateKey] = entry.id
        }
        if let selectedDevice {
            preferredIDByKey[selectedDevice.duplicateKey] = selectedDevice.id
        }

        // A physical device can appear as multiple Core Bluetooth peers while
        // advertising the same public name. Keep one stable picker row per name.
        entries = Self.removingDuplicateNames(
            from: entries,
            preferredIDByKey: preferredIDByKey
        )
        let currentDevices = Self.removingDuplicateNames(
            from: currentDevices,
            preferredIDByKey: preferredIDByKey
        )
        let currentByID = Dictionary(
            uniqueKeysWithValues: currentDevices.map { ($0.id, $0) }
        )
        let currentByKey = Dictionary(
            uniqueKeysWithValues: currentDevices.map { ($0.duplicateKey, $0) }
        )

        for index in entries.indices {
            let id = entries[index].id
            if let current = currentByID[id] {
                entries[index] = current
            } else if id != selectedDevice?.id,
                      let current = currentByKey[entries[index].duplicateKey] {
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
            if let duplicateIndex = entries.firstIndex(where: {
                $0.duplicateKey == selectedDevice.duplicateKey
            }) {
                entries[duplicateIndex] = selectedDevice
            } else {
                entries.insert(selectedDevice, at: 0)
            }
        }

        var knownIDs = Set(entries.map(\.id))
        var knownKeys = Set(entries.map(\.duplicateKey))
        for device in currentDevices
        where !knownIDs.contains(device.id) && !knownKeys.contains(device.duplicateKey) {
            entries.append(device)
            knownIDs.insert(device.id)
            knownKeys.insert(device.duplicateKey)
        }

        entries = Self.removingDuplicateNames(
            from: entries,
            preferredIDByKey: selectedDevice.map {
                [$0.duplicateKey: $0.id]
            } ?? [:]
        )

        guard let selectedID = selectedDevice?.id,
              let selectedIndex = entries.firstIndex(where: { $0.id == selectedID }),
              selectedIndex != entries.startIndex else {
            return
        }
        let entry = entries.remove(at: selectedIndex)
        entries.insert(entry, at: 0)
    }

    private static func removingDuplicateNames(
        from entries: [ProximityDevicePickerEntry],
        preferredIDByKey: [String: UUID]
    ) -> [ProximityDevicePickerEntry] {
        var result: [ProximityDevicePickerEntry] = []
        var indexByKey: [String: Int] = [:]

        for entry in entries {
            if let index = indexByKey[entry.duplicateKey] {
                if preferredIDByKey[entry.duplicateKey] == entry.id {
                    result[index] = entry
                }
            } else {
                indexByKey[entry.duplicateKey] = result.endIndex
                result.append(entry)
            }
        }
        return result
    }
}
