import Foundation

nonisolated enum AIServiceType: String, CaseIterable, Codable, Sendable {
    case chatCompletions, responses, messages

    var title: String {
        switch self {
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        case .messages: "Messages"
        }
    }
    var endpointExample: String {
        switch self {
        case .chatCompletions: "https://api.openai.com/v1/chat/completions"
        case .responses: "https://api.openai.com/v1/responses"
        case .messages: "https://api.anthropic.com/v1/messages"
        }
    }
}

nonisolated enum AIReasoningEffort: String, CaseIterable, Codable, Sendable {
    case none, minimal, low, medium, high, xhigh, max
}
nonisolated enum MessagesThinking: String, CaseIterable, Codable, Sendable {
    case endpointDefault, disabled, adaptive
}
nonisolated enum MessagesEffort: String, CaseIterable, Codable, Sendable {
    case low, medium, high, xhigh, max
}
nonisolated struct ChatCompletionsDefaults: Equatable, Codable, Sendable {
    var temperature: Double?
    var reasoningEffort: AIReasoningEffort?
}
nonisolated struct ResponsesDefaults: Equatable, Codable, Sendable {
    var temperature: Double?
    var reasoningEffort: AIReasoningEffort?
}
nonisolated struct MessagesDefaults: Equatable, Codable, Sendable {
    var temperature: Double?
    var thinking: MessagesThinking = .endpointDefault
    var effort: MessagesEffort?
}
nonisolated enum AIServiceDefaults: Equatable, Codable, Sendable {
    case chatCompletions(ChatCompletionsDefaults)
    case responses(ResponsesDefaults)
    case messages(MessagesDefaults)

    init(service: AIServiceType) {
        switch service {
        case .chatCompletions: self = .chatCompletions(ChatCompletionsDefaults())
        case .responses: self = .responses(ResponsesDefaults())
        case .messages: self = .messages(MessagesDefaults())
        }
    }
    var service: AIServiceType {
        switch self {
        case .chatCompletions: .chatCompletions
        case .responses: .responses
        case .messages: .messages
        }
    }
    var temperature: Double? {
        switch self {
        case .chatCompletions(let value): value.temperature
        case .responses(let value): value.temperature
        case .messages(let value): value.temperature
        }
    }
    func withTemperature(_ temperature: Double?) -> Self {
        switch self {
        case .chatCompletions(var value): value.temperature = temperature; return .chatCompletions(value)
        case .responses(var value): value.temperature = temperature; return .responses(value)
        case .messages(var value): value.temperature = temperature; return .messages(value)
        }
    }
}

nonisolated struct AIServiceConfiguration: Equatable, Codable, Sendable {
    let service: AIServiceType
    var endpoint = ""
    var model = ""
    var defaults: AIServiceDefaults
    var totalBudget = 65_536
    var outputLimit = 16_384
    var concurrency = 3

    init(service: AIServiceType) { self.service = service; defaults = AIServiceDefaults(service: service) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.service == rhs.service && lhs.endpoint.utf8.elementsEqual(rhs.endpoint.utf8)
            && lhs.model.utf8.elementsEqual(rhs.model.utf8) && lhs.defaults == rhs.defaults
            && lhs.totalBudget == rhs.totalBudget && lhs.outputLimit == rhs.outputLimit && lhs.concurrency == rhs.concurrency
    }

    var usesPlainHTTP: Bool { URLComponents(string: endpoint)?.scheme?.lowercased() == "http" }
    var inputError: AIServiceInputError? {
        if !endpoint.isEmpty {
            guard URL(string: endpoint, encodingInvalidCharacters: false) != nil,
                  let url = URLComponents(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil,
                  endpoint == endpoint.trimmingCharacters(in: .whitespacesAndNewlines) else { return .invalidEndpoint }
        }
        guard defaults.service == service else { return .invalidDefaults }
        if let temperature = defaults.temperature, !temperature.isFinite || !(0...(service == .messages ? 1.0 : 2.0)).contains(temperature) {
            return .invalidTemperature
        }
        if case .messages(let value) = defaults, value.thinking != .adaptive, value.effort != nil { return .invalidDefaults }
        if totalBudget <= 0 { return .invalidTotalBudget }
        if outputLimit <= 0 || outputLimit >= totalBudget { return .invalidOutputLimit }
        if !(1...8).contains(concurrency) { return .invalidConcurrency }
        return nil
    }
}

nonisolated struct AIServiceEdit: Equatable, Sendable {
    var configuration: AIServiceConfiguration
    var temperature: String
    var totalBudget: String
    var outputLimit: String
    var concurrency: String
    var newCredential = ""

    init(configuration: AIServiceConfiguration) {
        self.configuration = configuration
        temperature = configuration.defaults.temperature.map { String($0) } ?? ""
        totalBudget = String(configuration.totalBudget)
        outputLimit = String(configuration.outputLimit)
        concurrency = String(configuration.concurrency)
    }

    func validatedConfiguration() throws -> AIServiceConfiguration {
        var value = configuration
        value.endpoint = value.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTemperature = temperature.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTemperature = rawTemperature.isEmpty ? nil : Double(rawTemperature)
        guard rawTemperature.isEmpty || parsedTemperature != nil else { throw AIServiceInputError.invalidTemperature }
        value.defaults = value.defaults.withTemperature(parsedTemperature)
        guard let budget = Int(totalBudget), budget > 0 else { throw AIServiceInputError.invalidTotalBudget }
        guard let output = Int(outputLimit), output > 0 else { throw AIServiceInputError.invalidOutputLimit }
        guard let count = Int(concurrency) else { throw AIServiceInputError.invalidConcurrency }
        value.totalBudget = budget; value.outputLimit = output; value.concurrency = count
        if let error = value.inputError { throw error }
        return value
    }
}

nonisolated enum AIServiceInputError: Error, Hashable, Sendable {
    case invalidEndpoint, invalidTemperature, invalidDefaults, invalidTotalBudget, invalidOutputLimit, invalidConcurrency
    case missingEndpoint, missingModel, missingCredential
    var message: String {
        switch self {
        case .invalidEndpoint: "请输入带 host 的完整 HTTP(S) URL，不允许 userinfo、fragment 或非法 URL 字符。"
        case .invalidTemperature: "温度须为有限数字：Messages 0–1，其他协议 0–2；留空表示未设置。"
        case .invalidDefaults: "请使用所选协议的原生默认值；Messages 仅 adaptive 可设置 effort。"
        case .invalidTotalBudget: "请求总预算 C 须为正整数。"
        case .invalidOutputLimit: "输出上限 O 须为正整数且小于 C。"
        case .invalidConcurrency: "并发数须为 1–8 的整数。"
        case .missingEndpoint: "请填写完整请求端点并保存后再校验。"
        case .missingModel: "请填写精确模型标识并保存后再校验。"
        case .missingCredential: "请填写新凭据并保存后再校验。"
        }
    }
}

nonisolated enum AIValidationStatus: String, Codable, Sendable {
    case unvalidated, validated, failed, needsRevalidation
    var title: String {
        switch self {
        case .unvalidated: "未校验"
        case .validated: "已校验"
        case .failed: "校验失败"
        case .needsRevalidation: "需要重新校验"
        }
    }
}
nonisolated struct AIServiceValidation: Equatable, Codable, Sendable {
    var status: AIValidationStatus = .unvalidated
    var baseline: AIValidationBaseline?
    var checkedAt: Date?
    var streaming: AIServiceCapability = .unknown
    var structured: AIServiceCapability = .unknown

    mutating func invalidate() {
        if status != .unvalidated { status = .needsRevalidation }
        streaming = .unknown
        structured = .unknown
    }
}
nonisolated struct AICredentialEnvelope: Equatable, Codable, Sendable {
    let formatVersion: Int
    let keyVersion: Int
    let combined: Data
}
nonisolated struct SavedAIService: Equatable, Codable, Sendable {
    var configuration: AIServiceConfiguration
    var credential: AICredentialEnvelope?
    var credentialVersion: Int64 = 0
    var validation = AIServiceValidation()

    var requestBaseline: AIValidationBaseline {
        AIValidationBaseline(service: configuration.service, endpoint: configuration.endpoint, model: configuration.model,
                             defaults: configuration.defaults, credentialVersion: credentialVersion,
                             outputLimit: configuration.outputLimit,
                             authentication: configuration.service == .messages ? .messages(version: MessagesAdapter.apiVersion) : .bearer,
                             store: configuration.service == .messages ? nil : false,
                             truncation: configuration.service == .responses ? .disabled : nil, probeContractVersion: 1)
    }
    var hasMatchingValidation: Bool {
        validation.status == .validated && validation.baseline == requestBaseline && credential != nil
            && !configuration.endpoint.isEmpty && !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
nonisolated struct AIServiceSettings: Equatable, Sendable {
    var configurations = Dictionary(uniqueKeysWithValues: AIServiceType.allCases.map {
        ($0, SavedAIService(configuration: AIServiceConfiguration(service: $0)))
    })
    var current: AIServiceType?
}
