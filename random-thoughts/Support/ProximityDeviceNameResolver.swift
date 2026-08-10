import Foundation

enum ProximityDeviceNameResolver {
    static func resolve(
        id: UUID,
        advertisedName: String?,
        peripheralName: String?,
        manufacturer: String?,
        model: String?,
        beaconDescription: String?
    ) -> String {
        let advertisedName = normalized(advertisedName)
        let peripheralName = normalized(peripheralName)
        let manufacturer = normalized(manufacturer)
        let model = normalized(model)

        if let advertisedName, !isGeneric(advertisedName) {
            return advertisedName
        }
        if let peripheralName, !isGeneric(peripheralName) {
            return peripheralName
        }
        if manufacturer == "Apple Inc.",
           let model,
           let friendlyName = appleDeviceNames[model] {
            return friendlyName
        }
        if let manufacturer, let model {
            return "\(manufacturer)/\(model)"
        }
        if let model {
            return model
        }
        if let beaconDescription = normalized(beaconDescription) {
            return beaconDescription
        }
        if let advertisedName {
            return advertisedName
        }
        if let peripheralName {
            return peripheralName
        }
        if let manufacturer {
            return manufacturer
        }
        return "未知蓝牙设备 · \(id.uuidString.prefix(4))"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isGeneric(_ value: String) -> Bool {
        switch value.lowercased() {
        case "iphone", "ipad", "apple watch", "bluetooth device", "unknown":
            true
        default:
            false
        }
    }
}
