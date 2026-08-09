import Foundation

struct ProximityDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rssi: Int
    var macAddress: String?

    var displayTitle: String {
        if let macAddress {
            return "\(name)（\(macAddress.uppercased())）"
        }
        return name
    }
}

enum ProximityBluetoothState: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

enum ProximityPresenceReason: String, Equatable, Sendable {
    case close
    case away
    case lost
}

struct ProximityConfiguration: Codable, Equatable, Sendable {
    var selectedDeviceID: UUID?
    var lockRSSI: Int?
    var unlockRSSI: Int?
    var lockDelay: TimeInterval
    var signalTimeout: TimeInterval
    var minimumScanRSSI: Int
    var passiveMode: Bool
    var wakeOnProximity: Bool
    var wakeWithoutUnlocking: Bool
    var pauseNowPlaying: Bool
    var useScreensaverToLock: Bool
    var turnOffDisplayOnLock: Bool

    static let `default` = ProximityConfiguration(
        selectedDeviceID: nil,
        lockRSSI: -80,
        unlockRSSI: -60,
        lockDelay: 5,
        signalTimeout: 60,
        minimumScanRSSI: -70,
        passiveMode: false,
        wakeOnProximity: false,
        wakeWithoutUnlocking: false,
        pauseNowPlaying: false,
        useScreensaverToLock: false,
        turnOffDisplayOnLock: false
    )
}

enum ProximityBluetoothEvent: Sendable {
    case state(ProximityBluetoothState)
    case devices([ProximityDevice])
    case signal(rssi: Int?, active: Bool)
    case presence(isPresent: Bool, reason: ProximityPresenceReason)
}
