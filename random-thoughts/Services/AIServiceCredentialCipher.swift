import CryptoKit
import Foundation

protocol AICredentialAccess: Sendable {
    func seal(_ credential: String) async throws -> AICredentialEnvelope
    func open(_ envelope: AICredentialEnvelope) async throws -> String
}

actor AIServiceCredentialCipher: AICredentialAccess {
    private let codec: AICredentialCodec
    init(key: Data, keyVersion: Int = 1, legacyKeys: [Int: Data] = [:]) {
        codec = AICredentialCodec(key: key, keyVersion: keyVersion, legacyKeys: legacyKeys)
    }
    private init(codec: AICredentialCodec) { self.codec = codec }
    static func bundled() -> AIServiceCredentialCipher { AIServiceCredentialCipher(codec: .bundled()) }
    func seal(_ credential: String) throws -> AICredentialEnvelope { try codec.seal(credential) }
    func open(_ envelope: AICredentialEnvelope) throws -> String { try codec.open(envelope) }
}

// Shared by the async credential boundary and the storage actor's synchronous transaction.
nonisolated struct AICredentialCodec: Sendable {
    private let key: Data
    private let keyVersion: Int
    private let legacyKeys: [Int: Data]
    init(key: Data, keyVersion: Int = 1, legacyKeys: [Int: Data] = [:]) {
        self.key = key; self.keyVersion = keyVersion; self.legacyKeys = legacyKeys
    }

    static func bundled() -> AICredentialCodec {
        // Stable application key v1. This prevents plaintext storage, not extraction from the application.
        AICredentialCodec(key: Data([
            0x64, 0x9a, 0x11, 0xc8, 0x3d, 0x72, 0xa6, 0xef, 0xb2, 0x41, 0x8c, 0x09, 0xdd, 0x37, 0x5e, 0xf0,
            0x23, 0x96, 0x7b, 0x45, 0xac, 0x18, 0xe2, 0x60, 0x8f, 0xd4, 0x31, 0x5a, 0x07, 0xb9, 0xce, 0x82
        ]))
    }

    func seal(_ credential: String) throws -> AICredentialEnvelope {
        guard key.count == 32 else { throw AICredentialError.encryptionFailed }
        do {
            let sealed = try AES.GCM.seal(Data(credential.utf8), using: SymmetricKey(data: key),
                                        authenticating: authenticationData(format: 2, key: keyVersion))
            guard let combined = sealed.combined else { throw AICredentialError.encryptionFailed }
            return AICredentialEnvelope(formatVersion: 2, keyVersion: keyVersion, combined: combined)
        } catch { throw AICredentialError.encryptionFailed }
    }

    func open(_ envelope: AICredentialEnvelope) throws -> String {
        guard (1...2).contains(envelope.formatVersion) else { throw AICredentialError.unsupportedFormat }
        guard let readingKey = envelope.keyVersion == keyVersion ? key : legacyKeys[envelope.keyVersion] else {
            throw AICredentialError.unknownKeyVersion
        }
        guard readingKey.count == 32 else { throw AICredentialError.authenticationFailed }
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.combined)
            let bytes = try AES.GCM.open(sealed, using: SymmetricKey(data: readingKey),
                authenticating: authenticationData(format: envelope.formatVersion, key: envelope.keyVersion))
            guard let value = String(data: bytes, encoding: .utf8) else { throw AICredentialError.authenticationFailed }
            return value
        } catch { throw AICredentialError.authenticationFailed }
    }

    private func authenticationData(format: Int, key: Int) -> Data {
        Data("DailyReports.AICredential.format\(format).key\(key)".utf8)
    }
}

nonisolated enum AICredentialError: Error, Hashable, Sendable {
    case unsupportedFormat, unknownKeyVersion, authenticationFailed, encryptionFailed
    var message: String {
        switch self {
        case .unsupportedFormat: "此凭据格式不受支持。原值保留，请使用兼容应用、重新填写或确认删除。"
        case .unknownKeyVersion: "此凭据的密钥版本未知。原值保留，请使用兼容应用、重新填写或确认删除。"
        case .authenticationFailed: "此凭据无法解密或认证。原值保留，请重新填写或确认删除。"
        case .encryptionFailed: "新凭据加密失败，完整旧配置及输入已保留，请重试保存。"
        }
    }
}
