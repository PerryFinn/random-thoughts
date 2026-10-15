import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct MessagesWireTests {
    @Test(arguments: MessagesThinking.allCases)
    func unsetControlsStayAbsentAndDisabledThinkingIsExplicit(_ thinking: MessagesThinking) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: MessagesFixture.completion("OK"))
        _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
            .execute(messagesRequest(endpoint: environment.transport.endpoint, defaults: .init(thinking: thinking)))
        let request = try #require(environment.transport.requests.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any])
        #expect(object["temperature"] == nil && object["output_config"] == nil)
        if thinking == .endpointDefault { #expect(object["thinking"] == nil) }
        else {
            let value = try #require(object["thinking"] as? [String: Any])
            #expect(value["type"] as? String == thinking.rawValue && value["budget_tokens"] == nil)
        }
    }

    @Test(arguments: [AIRequestIntent.extractFacts, .mergeFacts, .composeReport])
    func everySharedBusinessIntentUsesTheNativeMessagesSchema(_ intent: AIRequestIntent) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: MessagesFixture.completion("OK"))
        let request = messagesRequest(endpoint: environment.transport.endpoint, intent: intent, schema: ReportPayload.schema)
        #expect(try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production)).execute(request) == "OK")
        let sent = try #require(environment.transport.requests.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: sent)) as? [String: Any])
        let output = try #require(object["output_config"] as? [String: Any])
        #expect(output["effort"] == nil && output["format"] != nil)
        let canonical = String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        #expect(canonical == (try AIServiceClient.serializedFormat(ReportPayload.schema, configuration: request.configuration)))
    }

    @Test(arguments: ["max_tokens", "refusal", "model_context_window_exceeded", "tool_use", "pause_turn", "stop_sequence", "unknown"])
    func abnormalStopReasonsNeverReturnPartialText(_ reason: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: MessagesFixture.message("PARTIAL_TEXT_30", stop: reason)))
        await #expect(throws: reason == "refusal" ? AIRequestError.refusal : AIRequestError.incomplete) {
            try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint))
        }
    }

    @Test(arguments: ["empty", "missingText", "thinkingOnly", "tool", "unknown", "refusalDetails", "wrongRole", "wrongType", "missingStop"])
    func malformedOrNonTextMessagesCannotBeAcceptedAsReports(_ shape: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        var response = MessagesFixture.message("OK")
        switch shape {
        case "empty": response["content"] = [["type": "text", "text": " \n"]]
        case "missingText": response["content"] = [["type": "text"]]
        case "thinkingOnly": response["content"] = [["type": "thinking", "thinking": "PRIVATE_30", "signature": "signature"]]
        case "tool": response["content"] = [["type": "text", "text": "OK"], ["type": "tool_use", "id": "tool_30", "name": "synthetic", "input": [:]]]
        case "unknown": response["content"] = [["type": "future_block", "text": "OK"]]
        case "refusalDetails": response["stop_details"] = ["type": "refusal", "explanation": "PRIVATE_REFUSAL_30"]
        case "wrongRole": response["role"] = "user"
        case "wrongType": response["type"] = "other"
        case "missingStop": response.removeValue(forKey: "stop_reason")
        default: break
        }
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: response))
        await #expect(throws: (any Error).self) {
            try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint))
        }
    }

    @Test func structuredMessagesUsesTheNativeOutputConfigAlongsideAdaptiveEffort() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: MessagesFixture.completion(syntheticReportPayload))
        let request = messagesRequest(endpoint: environment.transport.endpoint, intent: .composeReport, schema: ReportPayload.schema,
            defaults: .init(thinking: .adaptive, effort: .high))
        let result = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production)).execute(request)
        #expect(result == syntheticReportPayload)
        let sent = try #require(environment.transport.requests.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: sent)) as? [String: Any])
        let output = try #require(object["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "high")
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema" && format["name"] == nil && format["strict"] == nil)
        #expect((format["schema"] as? [String: Any])?["required"] as? [String] == ReportPayload.keys)
        #expect(object["temperature"] == nil && object["tools"] == nil && object["response_format"] == nil)
    }

    @Test func messagesUsesNativeAuthenticationControlsAndOnlyTextContent() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        var response = MessagesFixture.message("")
        response["content"] = [["type": "thinking", "thinking": "PRIVATE_THINKING_30", "signature": "synthetic"],
                               ["type": "text", "text": "中文"], ["type": "redacted_thinking", "data": "PRIVATE_REDACTED_30"],
                               ["type": "text", "text": "👩🏽‍💻 e\u{301}"]]
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: response))
        let request = messagesRequest(endpoint: environment.transport.endpoint,
            defaults: .init(temperature: 0, thinking: .adaptive, effort: .max))
        let text = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production)).execute(request)
        #expect(text.utf8.elementsEqual("中文👩🏽‍💻 e\u{301}".utf8))
        let sent = try #require(environment.transport.requests.first)
        #expect(sent.url == environment.transport.endpoint && environment.transport.requests.count == 1)
        #expect(sent.value(forHTTPHeaderField: "x-api-key") == "SYNTHETIC_MESSAGES_KEY_30")
        #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: sent)) as? [String: Any])
        #expect(object["model"] as? String == "synthetic-messages-30" && object["system"] as? String == "Synthetic system")
        #expect(object["max_tokens"] as? Int == 4_096 && object["temperature"] as? Double == 0)
        #expect((object["thinking"] as? [String: Any])?["type"] as? String == "adaptive")
        #expect((object["output_config"] as? [String: Any])?["effort"] as? String == "max")
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(messages.count == 1 && messages[0]["role"] as? String == "user" && messages[0]["content"] as? String == "Synthetic user")
        #expect(["store", "truncation", "reasoning", "reasoning_effort", "max_output_tokens", "max_completion_tokens", "response_format", "text"]
            .allSatisfy { object[$0] == nil })
    }
}
