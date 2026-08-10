import Foundation

struct ProximityPresenceDetector: Sendable {
    struct SampleResult: Equatable, Sendable {
        var estimatedRSSI: Int
        var transition: ProximityPresenceReason?
    }

    struct TickResult: Equatable, Sendable {
        var signalWasLost: Bool
        var transition: ProximityPresenceReason?
    }

    private(set) var isPresent = true
    private var recentRSSIs: [Int] = []
    private var belowLockThresholdSince: Date?
    private var lastSignalAt: Date?
    private var reportedSignalLoss = false
    private let sampleLimit: Int

    init(sampleLimit: Int = 5) {
        self.sampleLimit = sampleLimit
    }

    mutating func reset(at date: Date, present: Bool = true) {
        isPresent = present
        recentRSSIs.removeAll(keepingCapacity: true)
        belowLockThresholdSince = nil
        lastSignalAt = date
        reportedSignalLoss = false
    }

    mutating func receive(
        rssi: Int,
        at date: Date,
        configuration: ProximityConfiguration
    ) -> SampleResult {
        lastSignalAt = date
        reportedSignalLoss = false

        var transition: ProximityPresenceReason?
        let closeThreshold = configuration.unlockRSSI
            ?? configuration.lockRSSI
            ?? -100

        if !isPresent, rssi >= closeThreshold {
            isPresent = true
            transition = .close
            recentRSSIs.removeAll(keepingCapacity: true)
            belowLockThresholdSince = nil
        }

        if recentRSSIs.count >= sampleLimit {
            recentRSSIs.removeFirst()
        }
        recentRSSIs.append(rssi)
        let estimatedRSSI = recentRSSIs.reduce(0, +) / recentRSSIs.count

        let lockThreshold = configuration.lockRSSI
            ?? configuration.unlockRSSI
            ?? -100

        if estimatedRSSI >= lockThreshold {
            belowLockThresholdSince = nil
        } else if isPresent, belowLockThresholdSince == nil {
            belowLockThresholdSince = date
        }

        if isPresent,
           let belowLockThresholdSince,
           date.timeIntervalSince(belowLockThresholdSince) >= configuration.lockDelay {
            isPresent = false
            self.belowLockThresholdSince = nil
            transition = .away
        }

        return SampleResult(estimatedRSSI: estimatedRSSI, transition: transition)
    }

    mutating func tick(
        at date: Date,
        configuration: ProximityConfiguration
    ) -> TickResult {
        if isPresent,
           let belowLockThresholdSince,
           date.timeIntervalSince(belowLockThresholdSince) >= configuration.lockDelay {
            isPresent = false
            self.belowLockThresholdSince = nil
            return TickResult(signalWasLost: false, transition: .away)
        }

        guard let lastSignalAt,
              date.timeIntervalSince(lastSignalAt) >= configuration.signalTimeout else {
            return TickResult(signalWasLost: false, transition: nil)
        }

        let shouldReportSignalLoss = !reportedSignalLoss
        reportedSignalLoss = true

        guard isPresent else {
            return TickResult(signalWasLost: shouldReportSignalLoss, transition: nil)
        }

        isPresent = false
        belowLockThresholdSince = nil
        recentRSSIs.removeAll(keepingCapacity: true)
        return TickResult(signalWasLost: shouldReportSignalLoss, transition: .lost)
    }
}

enum ProximityBluetoothScanPolicy {
    static func shouldScan(
        isDeviceDiscoveryRequested: Bool,
        hasSelectedDevice: Bool,
        isActivelyReadingRSSI: Bool
    ) -> Bool {
        isDeviceDiscoveryRequested
            || (hasSelectedDevice && !isActivelyReadingRSSI)
    }
}

enum ProximityAutomaticUnlockPolicy {
    static func isEnabled(configuration: ProximityConfiguration) -> Bool {
        configuration.selectedDeviceID != nil
            && configuration.unlockRSSI != nil
    }

    static func shouldAttempt(
        configuration: ProximityConfiguration,
        manualLock: Bool,
        isPresent: Bool,
        systemSleeping: Bool,
        displaySleeping: Bool
    ) -> Bool {
        isEnabled(configuration: configuration)
            && !manualLock
            && isPresent
            && !systemSleeping
            && !displaySleeping
    }
}

enum ProximityScreenUnlockPolicy {
    struct Actions: Equatable, Sendable {
        var shouldRunIntrudedScript: Bool
        var shouldResumePlayback: Bool
    }

    static func actions(
        elapsedSinceAutomaticUnlock: TimeInterval,
        automaticUnlockEnabled: Bool
    ) -> Actions {
        let wasManualUnlock = elapsedSinceAutomaticUnlock >= 10
        return Actions(
            shouldRunIntrudedScript: wasManualUnlock && automaticUnlockEnabled,
            shouldResumePlayback: wasManualUnlock
        )
    }
}
