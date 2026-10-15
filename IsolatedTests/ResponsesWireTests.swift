import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ResponsesWireTests {
    @Test func nativeOutputBlocksAreReadInOrderWithoutUsingTheSDKOnlyAggregate() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        var object = ResponsesFixture.response("unused")
        var message = ResponsesFixture.message("", status: "completed")
        message["content"] = [ResponsesFixture.part("中文"), ResponsesFixture.part("👩🏽‍💻"), ResponsesFixture.part(" e\u{301}")]
        object["output"] = [ResponsesFixture.reasoning(status: "completed"), message]
        object["output_text"] = "SDK_ONLY_MUST_NOT_BE_USED_29"
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: object))
        let result = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
            .execute(responsesRequest(endpoint: environment.transport.endpoint))
        #expect(result.utf8.elementsEqual("中文👩🏽‍💻 e\u{301}".utf8))
    }

    @Test(arguments: ["sdkOnly", "empty", "refusal", "tool", "unknownPart", "incomplete", "failed", "uncompletedMessage", "wrongRole"])
    func nonTextOrIncompleteOutputCannotBecomeACompleteReport(_ shape: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        var object = ResponsesFixture.response("OK"), message = ResponsesFixture.message("OK", status: "completed")
        switch shape {
        case "sdkOnly": object["output_text"] = "OK"; object["output"] = []
        case "empty": message["content"] = [ResponsesFixture.part(" \n")]
        case "refusal": message["content"] = [["type": "refusal", "refusal": "Synthetic refusal"]]
        case "tool": message = ["id": "tool", "type": "function_call", "status": "completed"]
        case "unknownPart": message["content"] = [["type": "unknown", "text": "OK"]]
        case "incomplete", "failed": object["status"] = shape
        case "uncompletedMessage": message["status"] = "in_progress"
        case "wrongRole": message["role"] = "user"
        default: break
        }
        if shape != "sdkOnly" { object["output"] = [message] }
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: object))
        await #expect(throws: (any Error).self) {
            try await ResponsesAdapter(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(responsesRequest(endpoint: environment.transport.endpoint))
        }
    }

    @Test func nativeSchemaUsesTextFormatAndCountsTheExactSerializedWrapper() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: responsesCompletion(syntheticReportPayload))
        var configuration = AIServiceConfiguration(service: .responses)
        configuration.endpoint = environment.transport.endpoint.absoluteString
        let adapter = ResponsesAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        #expect(try await adapter.execute(.init(intent: .composeReport, configuration: configuration, credential: "synthetic",
            instruction: "Synthetic", input: "Probe", schema: ReportPayload.schema, streaming: false)) == syntheticReportPayload)
        let request = try #require(environment.transport.requests.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any])
        #expect(object["temperature"] == nil && object["reasoning"] == nil)
        let text = try #require(object["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema" && format["name"] as? String == "daily_report")
        #expect(format["strict"] as? Bool == true)
        #expect((format["schema"] as? [String: Any])?["required"] as? [String] == ReportPayload.keys)
        let canonical = String(decoding: try JSONSerialization.data(withJSONObject: text, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        #expect(canonical == (try ResponsesAdapter.serializedFormat(ReportPayload.schema)))
    }

    @Test func nativeControlsAndOutputBlocksUseOnlyTheResponsesProtocol() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: responsesCompletion("OK"))
        var configuration = AIServiceConfiguration(service: .responses)
        configuration.endpoint = environment.transport.endpoint.absoluteString
        configuration.model = "synthetic/exact-responses"; configuration.outputLimit = 128
        configuration.defaults = .responses(.init(temperature: 0, reasoningEffort: AIReasoningEffort.none))
        let adapter = ResponsesAdapter(transport: AIHTTPTransport(configuration: environment.transport.session.configuration, time: .production))
        #expect(try await adapter.execute(.init(intent: .probe(.basic), configuration: configuration,
            credential: "SYNTHETIC_RESPONSES_KEY_29", instruction: "Synthetic only", input: "Probe", schema: nil, streaming: false)) == "OK")
        let request = try #require(environment.transport.requests.first)
        #expect(request.url?.absoluteString == configuration.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SYNTHETIC_RESPONSES_KEY_29")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any])
        #expect(object["model"] as? String == "synthetic/exact-responses")
        #expect(object["instructions"] as? String == "Synthetic only" && object["input"] as? String == "Probe")
        #expect(object["max_output_tokens"] as? Int == 128 && object["temperature"] as? Double == 0)
        #expect((object["reasoning"] as? [String: Any])?["effort"] as? String == "none")
        #expect(object["store"] as? Bool == false && object["truncation"] as? String == "disabled")
        #expect(object["messages"] == nil && object["response_format"] == nil && object["reasoning_effort"] == nil)
        #expect(object["max_completion_tokens"] == nil && object["max_tokens"] == nil && object["text"] == nil)
    }
}

func responsesCompletion(_ text: String, status: String = "completed") -> Data {
    try! JSONSerialization.data(withJSONObject: ResponsesFixture.response(text, status: status))
}
