import Foundation

nonisolated struct ResponsesAdapter: AIServiceAccess {
    let transport: AIHTTPTransport
    static func serializedFormat(_ schema: String) throws -> String {
        String(decoding: try encoder().encode(ResponsesText(schema: schema)), as: UTF8.self)
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    @concurrent func execute(_ request: AIRequest) async throws -> String {
        guard request.configuration.service == .responses else { throw AIRequestError.unsupportedService }
        guard case .responses(let defaults) = request.configuration.defaults,
              let url = URL(string: request.configuration.endpoint) else { throw AIRequestError.parameters }
        let body = ResponsesRequest(model: request.configuration.model, instructions: request.instruction, input: request.input,
            temperature: defaults.temperature, reasoning: defaults.reasoningEffort.map { .init(effort: $0.rawValue) },
            maxOutputTokens: request.configuration.outputLimit, store: false, truncation: "disabled", stream: request.streaming,
            text: try request.schema.map { try ResponsesText(schema: $0) })
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("Bearer \(request.credential)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try Self.encoder().encode(body)
        do {
            let data = try await transport.send(http, stream: request.streaming ? ResponsesStream() : nil, service: .responses)
            if request.streaming {
                var stream = ResponsesStream(); _ = try stream.append(data)
                return try stream.finish()
            }
            guard let output = try? JSONDecoder().decode(ResponsesOutput.self, from: data) else { throw AIRequestError.invalidResponse }
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

private nonisolated struct ResponsesRequest: Encodable {
    struct Reasoning: Encodable { let effort: String }
    let model: String
    let instructions: String
    let input: String
    let temperature: Double?
    let reasoning: Reasoning?
    let maxOutputTokens: Int
    let store: Bool
    let truncation: String
    let stream: Bool
    let text: ResponsesText?
    enum CodingKeys: String, CodingKey {
        case model, instructions, input, temperature, reasoning, store, truncation, stream, text
        case maxOutputTokens = "max_output_tokens"
    }
}

private nonisolated struct ResponsesText: Encodable {
    struct Format: Encodable {
        let type = "json_schema"
        let name = "daily_report"
        let strict = true
        let schema: AIJSONValue
    }
    let format: Format
    init(schema: String) throws {
        guard let value = try? JSONDecoder().decode(AIJSONValue.self, from: Data(schema.utf8)), case .object = value else {
            throw AIRequestError.parameters
        }
        format = Format(schema: value)
    }
}

nonisolated struct ResponsesOutput: Decodable {
    struct Item: Decodable {
        struct Content: Decodable, Equatable { let type: String; let text: String?; let refusal: String? }
        let id: String
        let type: String
        let status: String?
        let role: String?
        let content: [Content]?
    }
    struct Failure: Decodable {
        let code: String?; let type: String?; let param: String?
        var reason: AIRequestError { AIHTTPTransport.failure(status: 200, code: code ?? type, parameter: param, service: .responses) }
    }
    struct Incomplete: Decodable { let reason: String? }
    let id: String
    let object: String
    let status: String
    let output: [Item]
    let error: Failure?
    let incompleteDetails: Incomplete?
    enum CodingKeys: String, CodingKey { case id, object, status, output, error; case incompleteDetails = "incomplete_details" }

    func completedText() throws -> String {
        if let error { throw error.reason }
        if status == "failed" { throw AIRequestError.unknown }
        guard status == "completed", incompleteDetails == nil else { throw AIRequestError.incomplete }
        guard object == "response", !id.isEmpty, error == nil else { throw AIRequestError.invalidResponse }
        var text = ""
        for item in output {
            switch item.type {
            case "reasoning":
                guard item.status == nil || item.status == "completed" else { throw AIRequestError.incomplete }
            case "message":
                guard item.status == "completed" else { throw AIRequestError.incomplete }
                guard item.role == "assistant", let content = item.content, !content.isEmpty else { throw AIRequestError.invalidResponse }
                for part in content {
                    if part.type == "refusal" { throw AIRequestError.refusal }
                    guard part.type == "output_text", let value = part.text else { throw AIRequestError.invalidResponse }
                    text += value
                }
            default: throw AIRequestError.invalidResponse
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.invalidResponse }
        return text
    }
}
