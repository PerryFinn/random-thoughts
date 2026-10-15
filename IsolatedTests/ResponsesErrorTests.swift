import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ResponsesErrorTests {
    @Test(arguments: ["store", "truncation", "max_output_tokens", "temperature", "reasoning.effort", "response_format"],
          ["unsupported_parameter", "unsupported_value"])
    func aRejectedRequiredOrForeignFieldCannotBeHiddenByCapabilityFallback(_ field: String, _ code: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let data = try JSONSerialization.data(withJSONObject: ["error": ["type": "invalid_request_error", "code": code, "param": field]])
        environment.transport.respond(with: data, statusCode: 400)
        do {
            _ = try await ResponsesAdapter(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(responsesRequest(endpoint: environment.transport.endpoint, intent: .probe(.structured), schema: ReportPayload.schema))
            Issue.record("A required control was silently dropped")
        } catch { #expect(AIRequestError.reason(for: error) == .parameters) }
        #expect(environment.transport.requests.count == 1)
        let sent = try #require(environment.transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: body(of: sent)) as? [String: Any])
        #expect(body["store"] as? Bool == false && body["truncation"] as? String == "disabled")
    }

    @Test(arguments: [403, 404, 429])
    func statusAloneIsInsufficientConfigurationErrorEvidence(_ status: Int) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: Data(#"{"error":{"message":"RAW_UNKNOWN_ERROR_29"}}"#.utf8), statusCode: status)
        do {
            _ = try await ResponsesAdapter(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(responsesRequest(endpoint: environment.transport.endpoint))
            Issue.record("A failed HTTP response was accepted")
        } catch {
            #expect(AIRequestError.reason(for: error) == (status == 429 ? .serviceLimit : .unknown))
            #expect(!AIRequestError.reason(for: error).invalidatesConfiguration)
        }
    }

    @Test(arguments: [false, true])
    func failedResponseEnvelopesPreserveExplicitErrorEvidence(_ streaming: Bool) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        var failure = ResponsesFixture.response("", status: "failed")
        failure["output"] = []
        failure["error"] = ["code": "invalid_api_key", "message": "PRIVATE_RAW_ERROR_29"]
        let data = streaming
            ? ResponsesFixture.sse([["type": "response.failed", "sequence_number": 0, "response": failure]])
            : try JSONSerialization.data(withJSONObject: failure)
        environment.transport.respond(with: data)
        do {
            _ = try await ResponsesAdapter(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(responsesRequest(endpoint: environment.transport.endpoint, streaming: streaming))
            Issue.record("A failed response was accepted")
        } catch { #expect(AIRequestError.reason(for: error) == .authentication) }
    }

    @Test(arguments: ["stream", "text.format", "text.format.type", "text.format.schema"],
          ["unsupported_parameter", "unsupported_value"])
    func explicitOptionalRejectionIsCapabilityEvidenceOnlyForTheProbe(_ field: String, _ code: String) async throws {
        for generating in [false, true] {
            let environment = try IsolatedTestEnvironment(); defer { environment.close() }
            let error = try JSONSerialization.data(withJSONObject: ["error": ["type": "invalid_request_error", "code": code, "param": field,
                "message": "RAW_ERROR_MUST_NOT_ESCAPE_29"]])
            environment.transport.respond(with: error, statusCode: 400)
            let stage: AIProbeStage = field == "stream" ? .streaming : .structured
            let request = responsesRequest(endpoint: environment.transport.endpoint,
                intent: generating ? .composeReport : .probe(stage), schema: field == "stream" ? nil : ReportPayload.schema,
                streaming: field == "stream")
            do {
                _ = try await ResponsesAdapter(transport: .init(configuration: environment.transport.session.configuration, time: .production)).execute(request)
                Issue.record("An explicitly rejected field was accepted")
            } catch {
                #expect(AIRequestError.reason(for: error) == (generating ? .parameters : field == "stream" ? .streamingUnsupported : .structuredUnsupported))
            }
            #expect(environment.transport.requests.count == 1)
        }
    }
}

func responsesRequest(endpoint: URL, intent: AIRequestIntent = .probe(.basic), schema: String? = nil, streaming: Bool = false) -> AIRequest {
    var configuration = AIServiceConfiguration(service: .responses)
    configuration.endpoint = endpoint.absoluteString; configuration.model = "synthetic-responses-29"
    return .init(intent: intent, configuration: configuration, credential: "SYNTHETIC_RESPONSES_KEY_29",
                 instruction: "Synthetic only", input: "Synthetic probe", schema: schema, streaming: streaming)
}
