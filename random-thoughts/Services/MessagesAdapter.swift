import Foundation

nonisolated struct MessagesAdapter: AIServiceAccess {
    static let apiVersion = "2023-06-01"
    let transport: AIHTTPTransport

    static func serializedFormat(_ schema: String, defaults: MessagesDefaults) throws -> String {
        String(decoding: try encoder().encode(MessagesOutputConfig(defaults: defaults, schema: schema)), as: UTF8.self)
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    @concurrent func execute(_ request: AIRequest) async throws -> String {
        guard request.configuration.service == .messages else { throw AIRequestError.unsupportedService }
        guard request.configuration.inputError == nil, case .messages(let defaults) = request.configuration.defaults,
              let url = URL(string: request.configuration.endpoint), url.host != nil else { throw AIRequestError.parameters }
        let input: AIJSONValue = request.additionalInputs.isEmpty ? .string(request.input) : .array(
            ([request.input] + request.additionalInputs).map { .object(["type": .string("text"), "text": .string($0)]) })
        let body = MessagesRequest(model: request.configuration.model, system: request.instruction,
            messages: [.init(role: "user", content: input)], maxTokens: request.configuration.outputLimit,
            temperature: defaults.temperature, thinking: defaults.thinking == .endpointDefault ? nil : .init(type: defaults.thinking.rawValue),
            outputConfig: request.schema == nil && defaults.effort == nil ? nil : try MessagesOutputConfig(defaults: defaults, schema: request.schema),
            stream: request.streaming)
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue(request.credential, forHTTPHeaderField: "x-api-key")
        http.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try Self.encoder().encode(body)
        do {
            let data = try await transport.send(http, stream: request.streaming ? MessagesStream() : nil, service: .messages)
            if request.streaming {
                var stream = MessagesStream(); _ = try stream.append(data)
                return try stream.finish()
            }
            guard let output = try? JSONDecoder().decode(MessagesOutput.self, from: data) else { throw AIRequestError.invalidResponse }
            return try output.completedText()
        } catch {
            let reason = AIRequestError.reason(for: error)
            let expected: AIRequestError?
            switch request.intent {
            case .probe(.streaming): expected = .streamingUnsupported
            case .probe(.structured): expected = .structuredUnsupported
            default: expected = nil
            }
            if [.streamingUnsupported, .structuredUnsupported].contains(reason), reason != expected { throw AIRequestError.parameters }
            throw error
        }
    }
}

private nonisolated struct MessagesRequest: Encodable {
    struct Message: Encodable { let role: String; let content: AIJSONValue }
    struct Thinking: Encodable { let type: String }
    let model: String
    let system: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double?
    let thinking: Thinking?
    let outputConfig: MessagesOutputConfig?
    let stream: Bool
    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature, thinking, stream
        case maxTokens = "max_tokens", outputConfig = "output_config"
    }
}

private nonisolated struct MessagesOutputConfig: Encodable {
    struct Format: Encodable { let type = "json_schema"; let schema: AIJSONValue }
    let effort: String?
    let format: Format?
    init(defaults: MessagesDefaults, schema: String?) throws {
        effort = defaults.effort?.rawValue
        format = try schema.map {
            guard let value = try? JSONDecoder().decode(AIJSONValue.self, from: Data($0.utf8)), case .object = value else {
                throw AIRequestError.parameters
            }
            return Format(schema: value)
        }
    }
}

nonisolated struct MessagesOutput: Decodable {
    struct Content: Decodable { let type: String; let text: String?; let signature: String? }
    struct StopDetails: Decodable { let type: String }
    let id: String
    let type: String
    let role: String
    let content: [Content]
    let stopReason: String?
    let stopSequence: String?
    let stopDetails: StopDetails?
    enum CodingKeys: String, CodingKey {
        case id, type, role, content
        case stopReason = "stop_reason", stopSequence = "stop_sequence", stopDetails = "stop_details"
    }

    func completedText() throws -> String {
        guard type == "message", role == "assistant", !id.isEmpty else { throw AIRequestError.invalidResponse }
        try Self.requireCompletion(reason: stopReason, sequence: stopSequence, details: stopDetails)
        var text = ""
        for part in content {
            switch part.type {
            case "text":
                guard let value = part.text else { throw AIRequestError.invalidResponse }
                text += value
            case "thinking", "redacted_thinking": break
            default: throw AIRequestError.invalidResponse
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.invalidResponse }
        return text
    }
    static func requireCompletion(reason: String?, sequence: String?, details: StopDetails?) throws {
        if reason == "refusal" || details?.type == "refusal" { throw AIRequestError.refusal }
        guard reason == "end_turn", sequence == nil, details == nil else { throw AIRequestError.incomplete }
    }
}
