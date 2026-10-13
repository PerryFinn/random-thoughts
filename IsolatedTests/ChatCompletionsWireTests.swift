import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ChatCompletionsWireTests {
    @Test(arguments: ["null", "[]"])
    func emptyOptionalToolCallsStillRepresentATextCompletion(_ absentCalls: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: Data("{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"OK\",\"tool_calls\":\(absentCalls),\"function_call\":null},\"finish_reason\":\"stop\"}]}".utf8))
        let adapter = ChatCompletionsAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        var config = AIServiceConfiguration(service: .chatCompletions); config.endpoint = environment.transport.endpoint.absoluteString
        #expect(try await adapter.execute(.init(intent: .probe(.basic), configuration: config, credential: "synthetic",
            instruction: "probe", input: "probe", schema: nil, streaming: false)) == "OK")
    }
    @Test func nativeSchemaEncodingMatchesTheExactTextUsedForOfflineCounting() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: completion(syntheticReportPayload))
        let adapter = ChatCompletionsAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        var config = AIServiceConfiguration(service: .chatCompletions); config.endpoint = environment.transport.endpoint.absoluteString
        _ = try await adapter.execute(.init(intent: .composeReport, configuration: config, credential: "synthetic",
            instruction: "Synthetic", input: "Probe", schema: ReportPayload.schema, streaming: false))
        let request = try #require(environment.transport.requests.first)
        let value = try #require(try JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any])
        let format = try #require(value["response_format"])
        let canonical = String(decoding: try JSONSerialization.data(withJSONObject: format, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        #expect(canonical == (try ChatCompletionsAdapter.serializedFormat(ReportPayload.schema)))
    }
    @Test func nativeControlsAndExactEndpointAreSentWithoutOtherProtocolFields() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: completion("OK"))
        let adapter = ChatCompletionsAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        var config = AIServiceConfiguration(service: .chatCompletions)
        config.endpoint = environment.transport.endpoint.absoluteString
        config.model = "synthetic/exact"; config.outputLimit = 128
        config.defaults = .chatCompletions(.init(temperature: 0, reasoningEffort: AIReasoningEffort.none))
        let result = try await adapter.execute(.init(intent: .probe(.basic), configuration: config, credential: "SYNTHETIC_BEARER_28",
            instruction: "Synthetic", input: "Probe", schema: nil, streaming: false))
        #expect(result == "OK")
        let request = try #require(environment.transport.requests.first)
        #expect(request.url?.absoluteString == config.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SYNTHETIC_BEARER_28")
        let object = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
        #expect(object["max_completion_tokens"] as? Int == 128)
        #expect(object["temperature"] as? Double == 0)
        #expect(object["reasoning_effort"] as? String == "none")
        #expect(object["store"] as? Bool == false)
        #expect(object["max_tokens"] == nil && object["truncation"] == nil && object["response_format"] == nil)
    }

    @Test func aWrongChoiceIndexCannotBeAcceptedAsTheSingleCompletion() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: Data(#"{"choices":[{"index":1,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#.utf8))
        let adapter = ChatCompletionsAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        var config = AIServiceConfiguration(service: .chatCompletions); config.endpoint = environment.transport.endpoint.absoluteString
        do {
            _ = try await adapter.execute(.init(intent: .probe(.basic), configuration: config, credential: "synthetic",
                instruction: "probe", input: "probe", schema: nil, streaming: false))
            Issue.record("An invalid completion index was accepted")
        } catch { #expect(error as? AIRequestError == .invalidResponse) }
    }
}

func completion(_ text: String, finish: String = "stop") -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["index": 0, "message": ["role": "assistant", "content": text], "finish_reason": finish]]])
}
func body(of request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { throw AIRequestError.invalidResponse }
    stream.open(); defer { stream.close() }
    var result = Data(), bytes = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        guard count >= 0 else { throw AIRequestError.invalidResponse }
        if count == 0 { break }; result.append(contentsOf: bytes.prefix(count))
    }
    return result
}
