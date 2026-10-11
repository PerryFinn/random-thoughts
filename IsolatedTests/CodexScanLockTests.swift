import Darwin
import Foundation
import Testing
@testable import random_thoughts

@MainActor
@Suite(.serialized)
struct CodexScanLockTests {
    @Test func aDifferentSourceDoesNotQueueBehindAnotherProcess() async throws {
        let held = try IsolatedTestEnvironment()
        let independent = try IsolatedTestEnvironment()
        defer { held.close(); independent.close() }
        let holder = try await holdScanLock(held)
        defer { holder.release() }
        try JSONSerialization.data(withJSONObject: ["scenario": "scan", "currentPages": [[]], "archivedPages": [[]]])
            .write(to: independent.directory.appendingPathComponent("fixture.json"))
        let reader = CodexDataSourceReader(homeDirectory: independent.directory,
            environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
            homebrewDirectories: [], scanLockDirectory: held.directory.appendingPathComponent("locks"), scanLockTimeout: 0.05)
        let result = try await reader.scan(scanIdentity(independent), day: ReportDay(date: independent.clock.now, timeZone: .gmt), progress: { _ in })
        #expect(result.sessions.isEmpty)
        #expect(holder.process.isRunning)
        try expectScanChildReaped(independent)
    }

    @Test(arguments: ["release", "cancel", "timeout"])
    func anotherProcessSerializesTheSameSourceAndWaitingCanEndWithoutStartingAChild(_ ending: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let fixture: [String: Any] = ["scenario": "scan", "currentPages": [[]], "archivedPages": [[]]]
        try JSONSerialization.data(withJSONObject: fixture).write(to: environment.directory.appendingPathComponent("fixture.json"))
        let holder = try await holdScanLock(environment)
        defer { holder.release() }
        let observer = ScanProgressObserver()
        let reader = CodexDataSourceReader(homeDirectory: environment.directory,
            environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
            homebrewDirectories: [], scanLockDirectory: environment.directory.appendingPathComponent("locks"),
            scanLockTimeout: ending == "timeout" ? 0.05 : 30)
        let identity = try scanIdentity(environment)
        let day = ReportDay(date: environment.clock.now, timeZone: .gmt)
        let scan = Task { try await reader.scan(identity, day: day, progress: { value in Task { await observer.receive(value) } }) }
        await observer.waitForContention()
        #expect(!FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("pid").path))
        if ending == "release" {
            holder.release()
            #expect(try await scan.value.sessions.isEmpty)
            try expectScanChildReaped(environment)
        } else {
            if ending == "cancel" { scan.cancel() }
            await #expect(throws: ending == "cancel" ? CodexSourceError.cancelled : .scanLockTimedOut) { try await scan.value }
            #expect(!FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("pid").path))
        }
        #expect(holder.process.isRunning || holder.process.terminationStatus == 0)
    }
}

actor ScanProgressObserver {
    private var contended = false
    private var observer: CheckedContinuation<Void, Never>?
    func receive(_ activity: CodexScanActivity) {
        if activity == .waitingForSource { contended = true; observer?.resume(); observer = nil }
    }
    func waitForContention() async {
        if !contended { await withCheckedContinuation { observer = $0 } }
    }
}

@MainActor
final class ScanLockHolder {
    let process: Process
    private let input: Pipe
    init(process: Process, input: Pipe) { self.process = process; self.input = input }
    func release() {
        guard process.isRunning else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data([1]))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

@MainActor
func holdScanLock(_ environment: IsolatedTestEnvironment) async throws -> ScanLockHolder {
    let path = environment.directory.appendingPathComponent("lock-ready").path
    #expect(mkfifo(path, 0o600) == 0)
    let ready = Task.detached {
        let descriptor = Darwin.open(path, O_RDONLY)
        guard descriptor >= 0 else { throw CodexSourceError.transportInterrupted }
        defer { Darwin.close(descriptor) }
        var byte: UInt8 = 0
        guard Darwin.read(descriptor, &byte, 1) == 1 else { throw CodexSourceError.transportInterrupted }
    }
    let process = Process()
    let input = Pipe()
    process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_STORAGE_PROBE"]))
    process.arguments = ["hold-scan-lock", environment.directory.path]
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    try await ready.value
    return ScanLockHolder(process: process, input: input)
}
