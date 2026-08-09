import Foundation
import SQLite3

@MainActor
final class BluetoothDeviceInfoResolver {
    struct DeviceInfo {
        var name: String?
        var macAddress: String?
    }

    private var pairedDatabase: OpaquePointer?
    private var otherDatabase: OpaquePointer?

    init() {
        sqlite3_open_v2(
            "/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.paired.db",
            &pairedDatabase,
            SQLITE_OPEN_READONLY,
            nil
        )
        sqlite3_open_v2(
            "/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.other.db",
            &otherDatabase,
            SQLITE_OPEN_READONLY,
            nil
        )
    }

    deinit {
        if let pairedDatabase {
            sqlite3_close(pairedDatabase)
        }
        if let otherDatabase {
            sqlite3_close(otherDatabase)
        }
    }

    func resolve(uuid: UUID) -> DeviceInfo {
        let identifier = uuid.uuidString
        if let info = query(
            database: pairedDatabase,
            sql: "SELECT Name, Address, ResolvedAddress FROM PairedDevices WHERE Uuid = ? COLLATE NOCASE",
            identifier: identifier,
            resolvedAddressColumn: 2
        ) {
            return info
        }

        if let info = query(
            database: otherDatabase,
            sql: "SELECT Name, Address FROM OtherDevices WHERE Uuid = ? COLLATE NOCASE",
            identifier: identifier,
            resolvedAddressColumn: nil
        ) {
            return info
        }

        return resolveFromLegacyBluetoothPreference(identifier: identifier)
    }

    private func query(
        database: OpaquePointer?,
        sql: String,
        identifier: String,
        resolvedAddressColumn: Int32?
    ) -> DeviceInfo? {
        guard let database else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, identifier, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let name = string(in: statement, column: 0)
        let address = resolvedAddressColumn.flatMap { string(in: statement, column: $0) }
            ?? string(in: statement, column: 1)

        return DeviceInfo(name: name, macAddress: normalizedMACAddress(address))
    }

    private func resolveFromLegacyBluetoothPreference(identifier: String) -> DeviceInfo {
        guard let preference = NSDictionary(
            contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist"
        ) else {
            return DeviceInfo()
        }

        let coreBluetoothCache = preference["CoreBluetoothCache"] as? NSDictionary
        let cachedDevice = coreBluetoothCache?[identifier] as? NSDictionary
        let address = cachedDevice?["DeviceAddress"] as? String

        var name: String?
        if let address,
           let deviceCache = preference["DeviceCache"] as? NSDictionary,
           let device = deviceCache[address] as? NSDictionary {
            name = normalizedString(device["Name"] as? String)
        }

        return DeviceInfo(name: name, macAddress: normalizedMACAddress(address))
    }

    private func string(in statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return normalizedString(String(cString: value))
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedMACAddress(_ value: String?) -> String? {
        guard let value = normalizedString(value) else { return nil }
        let parts = value.split(separator: " ")
        let address = parts.count > 1 ? String(parts[1]) : value
        return address.replacingOccurrences(of: "-", with: ":").uppercased()
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
}
