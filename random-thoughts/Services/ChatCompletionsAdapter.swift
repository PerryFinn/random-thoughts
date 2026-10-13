import Foundation

nonisolated struct ChatCompletionsAdapter: AIServiceAccess {
    let transport: AIHTTPTransport
    static func serializedFormat(_ schema: String) throws -> String {
        String(decoding: try encoder().encode(ChatResponseFormat(schema: schema)), as: UTF8.self)
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    @concurrent func execute(_ request: AIRequest) async throws -> String {
        guard request.configuration.service == .chatCompletions else { throw AIRequestError.unsupportedService }
        guard case .chatCompletions(let defaults) = request.configuration.defaults,
              let url = URL(string: request.configuration.endpoint) else { throw AIRequestError.parameters }
        let format = try request.schema.map { try ChatResponseFormat(schema: $0) }
        let body = ChatRequest(model: request.configuration.model,
                               messages: [.init(role: "system", content: request.instruction), .init(role: "user", content: request.input)],
                               temperature: defaults.temperature, reasoningEffort: defaults.reasoningEffort?.rawValue,
                               maxCompletionTokens: request.configuration.outputLimit, store: false,
                               stream: request.streaming, responseFormat: format)
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("Bearer \(request.credential)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try Self.encoder().encode(body)
        let data: Data
        do { data = try await transport.send(http, streaming: request.streaming) }
        catch {
            let reason = AIRequestError.reason(for: error)
            if case .composeReport = request.intent, [.streamingUnsupported, .structuredUnsupported].contains(reason) {
                throw AIRequestError.parameters
            }
            throw error
        }
        if request.streaming { return try ChatCompletion.parseStream(data) }
        return try ChatCompletion.parse(data)
    }
}

private nonisolated struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let temperature: Double?
    let reasoningEffort: String?
    let maxCompletionTokens: Int
    let store: Bool
    let stream: Bool
    let responseFormat: ChatResponseFormat?
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, store, stream
        case reasoningEffort = "reasoning_effort"
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

private nonisolated struct ChatResponseFormat: Encodable {
    struct Schema: Encodable { let name = "daily_report"; let strict = true; let schema: JSONValue }
    let type = "json_schema"
    let jsonSchema: Schema
    enum CodingKeys: String, CodingKey { case type; case jsonSchema = "json_schema" }
    init(schema: String) throws {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(schema.utf8)), case .object = value else {
            throw AIRequestError.parameters
        }
        jsonSchema = Schema(schema: value)
    }
}

private nonisolated enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

private nonisolated enum ChatCompletion {
    static func parse(_ data: Data) throws -> String {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = value["choices"] as? [[String: Any]], choices.count == 1, choices[0]["index"] as? Int == 0,
              let message = choices[0]["message"] as? [String: Any] else { throw AIRequestError.invalidResponse }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIRequestError.refusal }
        guard choices[0]["finish_reason"] as? String == "stop" else { throw AIRequestError.incomplete }
        guard message["role"] as? String == "assistant", !ChatCompletionsContent.hasCalls(message["tool_calls"]),
              !ChatCompletionsContent.hasCalls(message["function_call"]),
              let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIRequestError.invalidResponse
        }
        return content
    }
    static func parseStream(_ data: Data) throws -> String {
        var parser = ChatCompletionsStream()
        _ = try parser.append(data)
        return try parser.finish()
    }
}

nonisolated enum ChatCompletionsContent {
    static func hasCalls(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        return (value as? [Any])?.isEmpty != true
    }
}
