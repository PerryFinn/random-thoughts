import Foundation
@testable import random_thoughts

actor ControlledCodexSource: CodexSourceAccess {
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
    func holdNextCheck() { holdsNextCheck = true }
    func waitUntilCheckIsHeld() async {
        if heldCheck == nil { await withCheckedContinuation { checkObserver = $0 } }
    }
    // Deliberately ignores cancellation so tests can deliver an obsolete callback.
    func releaseCheck(version: String = "1.2.3") {
        heldCheck?.resume(returning: CodexVersion(version))
        heldCheck = nil
    }
}
