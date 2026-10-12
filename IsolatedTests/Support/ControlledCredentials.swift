import Foundation
@testable import random_thoughts

actor ControlledCredentials: AICredentialAccess {
    private let cipher: AIServiceCredentialCipher
    @MainActor init() { cipher = AIServiceCredentialCipher(key: Data(repeating: 0x21, count: 32)) }
    private var encryptionFailure = false
    private var holdsNextOpen = false
    private var heldOpen: CheckedContinuation<Void, Never>?
    private var openObserver: CheckedContinuation<Void, Never>?
    func failEncryption(_ value: Bool) { encryptionFailure = value }
    func seal(_ credential: String) async throws -> AICredentialEnvelope {
        if encryptionFailure { throw AICredentialError.encryptionFailed }
        return try await cipher.seal(credential)
    }
    func open(_ envelope: AICredentialEnvelope) async throws -> String {
        if holdsNextOpen {
            holdsNextOpen = false
            await withCheckedContinuation { continuation in
                heldOpen = continuation; openObserver?.resume(); openObserver = nil
            }
        }
        return try await cipher.open(envelope)
    }
    func holdNextOpen() { holdsNextOpen = true }
    func waitUntilOpenIsHeld() async { if heldOpen == nil { await withCheckedContinuation { openObserver = $0 } } }
    func releaseOpen() { heldOpen?.resume(); heldOpen = nil }
}
