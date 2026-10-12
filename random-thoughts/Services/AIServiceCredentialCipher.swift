import CryptoKit
import Foundation

protocol AICredentialAccess: Sendable {
    func seal(_ credential: String) async throws -> AICredentialEnvelope
    func open(_ envelope: AICredentialEnvelope) async throws -> String
}

actor AIServiceCredentialCipher: AICredentialAccess {
    private let key: Data
    private let keyVersion: Int
    init(key: Data, keyVersion: Int = 1) { self.key = key; self.keyVersion = keyVersion }

    static func bundled() -> AIServiceCredentialCipher {
        // Stable application key v1. This prevents plaintext storage, not extraction from the application.
        AIServiceCredentialCipher(key: Data([
            0x64, 0x9a, 0x11, 0xc8, 0x3d, 0x72, 0xa6, 0xef, 0xb2, 0x41, 0x8c, 0x09, 0xdd, 0x37, 0x5e, 0xf0,
            0x23, 0x96, 0x7b, 0x45, 0xac, 0x18, 0xe2, 0x60, 0x8f, 0xd4, 0x31, 0x5a, 0x07, 0xb9, 0xce, 0x82
        ]))
    }

    func seal(_ credential: String) throws -> AICredentialEnvelope {
        guard key.count == 32 else { throw AICredentialError.encryptionFailed }
        do {
            let sealed = try AES.GCM.seal(Data(credential.utf8), using: SymmetricKey(data: key),
                                        authenticating: authenticationData)
            guard let combined = sealed.combined else { throw AICredentialError.encryptionFailed }
            return AICredentialEnvelope(formatVersion: 1, keyVersion: keyVersion, combined: combined)
        } catch { throw AICredentialError.encryptionFailed }
    }

    func open(_ envelope: AICredentialEnvelope) throws -> String {
        guard envelope.formatVersion == 1 else { throw AICredentialError.unsupportedFormat }
        guard envelope.keyVersion == keyVersion else { throw AICredentialError.unknownKeyVersion }
        guard key.count == 32 else { throw AICredentialError.authenticationFailed }
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.combined)
            let bytes = try AES.GCM.open(sealed, using: SymmetricKey(data: key), authenticating: authenticationData)
            guard let value = String(data: bytes, encoding: .utf8) else { throw AICredentialError.authenticationFailed }
            return value
        } catch { throw AICredentialError.authenticationFailed }
    }

    private var authenticationData: Data { Data("DailyReports.AICredential.format1.key\(keyVersion)".utf8) }
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
