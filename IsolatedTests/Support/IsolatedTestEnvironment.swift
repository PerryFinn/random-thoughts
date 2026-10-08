import Foundation
import Testing

@MainActor
final class IsolatedTestEnvironment {
    let directory: URL
    let databaseURL: URL
    let credentialKey = Data(repeating: 0x21, count: 32)
    let defaults: UserDefaults
    let clock = ControlledClock()
    let transport = SyntheticTransport()
    private let suiteName = "com.perryfinn.random-thoughts.isolated.\(UUID().uuidString)"
    private var isClosed = false

    init() throws {
        let variables = ProcessInfo.processInfo.environment
        guard let root = variables["RANDOM_THOUGHTS_TEST_ROOT"],
              variables["CFFIXED_USER_HOME"] == root + "/home",
              let defaults = UserDefaults(suiteName: suiteName) else {
            throw EnvironmentError.missingIsolation
        }
        directory = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directory.appendingPathComponent("reports.sqlite")
        self.defaults = defaults
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        transport.close()
        clock.cancelAll()
        defaults.removePersistentDomain(forName: suiteName)
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove the isolated test directory")
        }
    }

    private enum EnvironmentError: Error {
        case missingIsolation
    }
}

@MainActor
final class ControlledClock {
    private(set) var now = Date(timeIntervalSince1970: 1_000)
    private var sleepCount = 0
    private var sleepers: [UUID: (Date, CheckedContinuation<Void, any Error>)] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(for seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers[id] = (now.addingTimeInterval(seconds), continuation)
                sleepCount += 1
                let ready = observers.filter { $0.0 <= sleepCount }
                observers.removeAll { $0.0 <= sleepCount }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }

    func waitForSleep(number: Int) async {
        guard sleepCount < number else { return }
        await withCheckedContinuation { observers.append((number, $0)) }
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let ready = sleepers.filter { $0.value.0 <= now }.map(\.key)
        ready.forEach { sleepers.removeValue(forKey: $0)?.1.resume() }
    }

    func cancelAll() {
        let pending = sleepers.values.map(\.1)
        sleepers.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
        observers.forEach { $0.1.resume() }
        observers.removeAll()
    }
}
