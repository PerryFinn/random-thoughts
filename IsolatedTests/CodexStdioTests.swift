import Darwin
import Foundation
import Testing
@testable import random_thoughts

@MainActor
@Suite(.serialized)
struct CodexStdioTests {
    @Test func aMissingEntryAtLaunchReturnsAFixedErrorWithoutFallback() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let reader = CodexDataSourceReader(homeDirectory: environment.directory, environment: [:], homebrewDirectories: [])
        let identity = CodexSourceIdentity(executablePath: environment.directory.appendingPathComponent("missing-codex").path,
                                           dataDirectory: environment.directory.path)
        await #expect(throws: CodexSourceError.launchFailed) { _ = try await reader.check(identity) }
        #expect(!FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("pid").path))
    }

    @Test(arguments: ["success", "empty", "archived", "unknown", "large", "old-version", "no-version"])
    func realStdioChecksStableMethodsWithoutStartingOrResumingAThread(_ scenario: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        try JSONSerialization.data(withJSONObject: ["scenario": scenario]).write(to: environment.directory.appendingPathComponent("fixture.json"))
        let binary = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"])
        let reader = CodexDataSourceReader(homeDirectory: environment.directory,
                                          environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
                                          homebrewDirectories: [])
        let version = try await reader.check(CodexSourceIdentity(executablePath: binary, dataDirectory: environment.directory.path))
        #expect(version?.description == (scenario == "old-version" ? "0.1.0" : scenario == "no-version" ? nil : "9.8.7"))
        try expectChildWasReaped(in: environment.directory)
    }

    @Test(arguments: ["handshake", "method", "parameters", "schema-list", "schema-read", "read", "malformed", "transport", "timeout"])
    func protocolFailuresExposeOnlyFixedErrorsAndReapTheOperation(_ scenario: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        try JSONSerialization.data(withJSONObject: ["scenario": scenario]).write(to: environment.directory.appendingPathComponent("fixture.json"))
        let reader = CodexDataSourceReader(homeDirectory: environment.directory,
                                          environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
                                          homebrewDirectories: [], timeout: scenario == "timeout" ? 1 : 5)
        let binary = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"])
        let expected: CodexSourceError
        switch scenario {
        case "handshake": expected = .handshakeFailed
        case "method": expected = .methodUnsupported
        case "parameters": expected = .parametersUnsupported
        case "read": expected = .readFailed
        case "transport": expected = .transportInterrupted
        case "timeout": expected = .timedOut
        default: expected = .schemaUnsupported
        }
        await #expect(throws: expected) {
            _ = try await reader.check(CodexSourceIdentity(executablePath: binary, dataDirectory: environment.directory.path))
        }
        try expectChildWasReaped(in: environment.directory)
    }

    @Test func cancellingABlockedRealPipeReturnsWithoutLeavingTheChildRunning() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        try JSONSerialization.data(withJSONObject: ["scenario": "blocked"]).write(to: environment.directory.appendingPathComponent("fixture.json"))
        let readyPath = environment.directory.appendingPathComponent("ready").path
        #expect(mkfifo(readyPath, 0o600) == 0)
        let ready = Task.detached { () throws -> Void in
            let descriptor = Darwin.open(readyPath, O_RDONLY)
            guard descriptor >= 0 else { throw CodexSourceError.transportInterrupted }
            defer { Darwin.close(descriptor) }
            var byte: UInt8 = 0
            guard Darwin.read(descriptor, &byte, 1) == 1 else { throw CodexSourceError.transportInterrupted }
        }
        let reader = CodexDataSourceReader(homeDirectory: environment.directory,
                                          environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
                                          homebrewDirectories: [])
        let identity = CodexSourceIdentity(executablePath: try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"]),
                                           dataDirectory: environment.directory.path)
        let operation = Task { try await reader.check(identity) }
        try await ready.value
        operation.cancel()
        await #expect(throws: CodexSourceError.cancelled) { try await operation.value }
        try expectChildWasReaped(in: environment.directory)
    }

    private func expectChildWasReaped(in directory: URL) throws {
        let pid = try #require(Int32(String(decoding: Data(contentsOf: directory.appendingPathComponent("pid")), as: UTF8.self)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
