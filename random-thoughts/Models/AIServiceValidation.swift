import Foundation

nonisolated struct AIServiceStorageEvent: Equatable, Sendable {
    enum Operation: String, Sendable { case configuration, currentSelection, credentialDeletion }
    enum Result: String, Sendable { case success, failure }
    let operation: Operation
    let result: Result
}

nonisolated enum AIServiceCapability: String, Codable, Sendable {
    case supported, unsupported, unknown
    var title: String {
        switch self { case .supported: "支持"; case .unsupported: "不支持"; case .unknown: "未知" }
    }
}
nonisolated enum AIAuthentication: Equatable, Codable, Sendable {
    case bearer
    case messages(version: String)
}
nonisolated enum AITruncation: String, Codable, Sendable { case disabled }

nonisolated struct AIValidationBaseline: Equatable, Codable, Sendable {
    let service: AIServiceType
    let endpoint: String
    let model: String
    let defaults: AIServiceDefaults
    let credentialVersion: Int64
    let outputLimit: Int
    let authentication: AIAuthentication
    let store: Bool?
    let truncation: AITruncation?
    let probeContractVersion: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.service == rhs.service && lhs.endpoint.utf8.elementsEqual(rhs.endpoint.utf8)
            && lhs.model.utf8.elementsEqual(rhs.model.utf8) && lhs.defaults == rhs.defaults
            && lhs.credentialVersion == rhs.credentialVersion && lhs.outputLimit == rhs.outputLimit
            && lhs.authentication == rhs.authentication && lhs.store == rhs.store && lhs.truncation == rhs.truncation
            && lhs.probeContractVersion == rhs.probeContractVersion
    }
}

nonisolated enum AICredentialStatus: Equatable, Sendable {
    case absent, readable, unreadable(AICredentialError)
    var title: String {
        switch self { case .absent: "未保存凭据"; case .readable: "已保存（掩码）"; case .unreadable: "已保存但无法读取" }
    }
}
