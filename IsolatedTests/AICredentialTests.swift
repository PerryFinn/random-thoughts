import CryptoKit
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct AICredentialTests {
    @Test func realAESGCMUsesRandomNoncesAndPreservesTheExactCredentialAcrossInstances() async throws {
        let key = Data(repeating: 0x31, count: 32)
        let cipher = AIServiceCredentialCipher(key: key)
        let raw = "SYNTHETIC_KEY_27\u{0} 秘密 👩🏽‍💻  "
        let first = try await cipher.seal(raw)
        let second = try await cipher.seal(raw)
        #expect(first.formatVersion == 2)
        #expect(first.keyVersion == 1)
        #expect(first.combined != second.combined)
        #expect(first.combined.prefix(12) != second.combined.prefix(12))
        #expect(try await cipher.open(first) == raw)
        #expect(try await AIServiceCredentialCipher(key: key).open(second) == raw)
        #expect(first.combined.range(of: Data(raw.utf8)) == nil)
        await #expect(throws: AICredentialError.encryptionFailed) {
            try await AIServiceCredentialCipher(key: Data()).seal(raw)
        }
    }

    @Test func unknownVersionsAndAuthenticationErrorsKeepTheOriginalEnvelope() async throws {
        let cipher = AIServiceCredentialCipher(key: Data(repeating: 0x31, count: 32))
        let envelope = try await cipher.seal("SYNTHETIC_AUTH_27")
        var damaged = envelope.combined
        damaged[damaged.count - 1] ^= 1
        for (value, expected) in [
            (AICredentialEnvelope(formatVersion: 99, keyVersion: 1, combined: envelope.combined), AICredentialError.unsupportedFormat),
            (AICredentialEnvelope(formatVersion: 1, keyVersion: 99, combined: envelope.combined), .unknownKeyVersion),
            (AICredentialEnvelope(formatVersion: 1, keyVersion: 1, combined: damaged), .authenticationFailed),
            (AICredentialEnvelope(formatVersion: 1, keyVersion: 1, combined: Data()), .authenticationFailed)
        ] {
            await #expect(throws: expected) { try await cipher.open(value) }
        }
        await #expect(throws: AICredentialError.authenticationFailed) {
            try await AIServiceCredentialCipher(key: Data(repeating: 0x32, count: 32)).open(envelope)
        }
    }
}
