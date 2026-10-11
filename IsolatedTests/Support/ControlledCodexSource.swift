import Foundation
@testable import random_thoughts

actor ControlledCodexSource: CodexSourceAccess {
    private(set) var scanCount = 0
    private var sessionScan = CodexSessionScan(sessions: [], failures: [], version: nil)
    private var holdsNextScan = false
    private var scanFailure: CodexSourceError?
    private var heldScan: CheckedContinuation<CodexSessionScan, any Error>?
    private var scanObserver: CheckedContinuation<Void, Never>?
    private(set) var checkCount = 0
    private var failure: CodexSourceError?
    private var holdsNextCheck = false
    private var heldCheck: CheckedContinuation<CodexVersion?, any Error>?
    private var checkObserver: CheckedContinuation<Void, Never>?

    func resolve(_ configuration: CodexDataSourceConfiguration, rediscover: Bool) async -> CodexSourceSelection {
        var configuration = configuration
        if configuration.executablePath.isEmpty || rediscover { configuration.executablePath = "/synthetic/bin/codex" }
        return CodexSourceSelection(settings: CodexDataSourceSettings(
            configuration: configuration,
            resolvedDirectory: configuration.explicitDirectory.isEmpty ? "/synthetic/.codex" : configuration.explicitDirectory
        ))
    }

    func check(_ source: CodexSourceIdentity) async throws -> CodexVersion? {
        checkCount += 1
        if holdsNextCheck {
            holdsNextCheck = false
            return try await withCheckedThrowingContinuation { continuation in
                heldCheck = continuation
                checkObserver?.resume()
                checkObserver = nil
            }
        }
        if let failure { throw failure }
        return CodexVersion("9.8.7")
    }

    func failChecks(_ value: CodexSourceError?) { failure = value }
    func scan(_ source: CodexSourceIdentity, day: ReportDay,
              progress: @escaping @Sendable (CodexScanActivity) -> Void) async throws -> CodexSessionScan {
        progress(.reading)
        scanCount += 1
        if holdsNextScan {
            holdsNextScan = false
            return try await withCheckedThrowingContinuation { continuation in
                heldScan = continuation
                scanObserver?.resume()
                scanObserver = nil
            }
        }
        if let scanFailure { throw scanFailure }
        return sessionScan
    }
    func setScan(_ value: CodexSessionScan) { sessionScan = value }
    func failScans(_ value: CodexSourceError?) { scanFailure = value }
    func holdNextScan() { holdsNextScan = true }
    func waitUntilScanIsHeld() async {
        if heldScan == nil { await withCheckedContinuation { scanObserver = $0 } }
    }
    func releaseScan(_ value: CodexSessionScan) { heldScan?.resume(returning: value); heldScan = nil }
    func holdNextCheck() { holdsNextCheck = true }
    func waitUntilCheckIsHeld() async {
        if heldCheck == nil { await withCheckedContinuation { checkObserver = $0 } }
    }
    // Deliberately ignores cancellation so tests can deliver an obsolete callback.
    func releaseCheck(version: String = "1.2.3", error: CodexSourceError? = nil) {
        if let error { heldCheck?.resume(throwing: error) }
        else { heldCheck?.resume(returning: CodexVersion(version)) }
        heldCheck = nil
    }
}
