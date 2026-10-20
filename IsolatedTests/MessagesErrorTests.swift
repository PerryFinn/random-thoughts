import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct MessagesErrorTests {
    @Test(arguments: ["thinking: temporary service failure", "temperature: unable to complete this request",
                      "output_config.format: unknown failure"], [false, true])
    func mentioningAFieldWithoutRejectionEvidenceDoesNotRevokeQualification(_ message: String, _ streaming: Bool) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let response: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "message": message]]
        environment.transport.respond(with: streaming ? MessagesFixture.sse([response]) : try JSONSerialization.data(withJSONObject: response),
                                       statusCode: streaming ? 200 : 400)
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: .composeReport, streaming: streaming))
            Issue.record("A failed request was accepted")
        } catch {
            let reason = AIRequestError.reason(for: error)
            #expect(reason == .unknown && !reason.invalidatesConfiguration)
            #expect(!reason.message.contains(message))
        }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func explicitDisabledThinkingRejectionRequiresConfigurationRevalidation(_ streaming: Bool) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let message = #"To turn thinking off on this model, send "thinking": {"type": "between_tools"} instead of {"type": "disabled"}."#
        let response: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "message": message]]
        environment.transport.respond(with: streaming ? MessagesFixture.sse([response]) : try JSONSerialization.data(withJSONObject: response),
                                       statusCode: streaming ? 200 : 400)
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: .composeReport, streaming: streaming,
                                         defaults: .init(thinking: .disabled)))
            Issue.record("The model explicitly rejected disabled thinking")
        } catch {
            let reason = AIRequestError.reason(for: error)
            #expect(reason == .parameters && reason.invalidatesConfiguration)
        }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: ["anthropic-version: unsupported version", "thinking: Invalid discriminator", "output_config.effort: Invalid effort",
                      "output_config.format: Invalid JSON schema", "stream: Input should be a valid boolean"])
    func nativeFieldValidationCannotBecomeAnOptionalCapabilityRejection(_ message: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let error: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "message": message]]
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: error), statusCode: 400)
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: .probe(.structured), schema: ReportPayload.schema))
            Issue.record("A native field validation error was accepted")
        } catch { #expect(AIRequestError.reason(for: error) == .parameters) }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: ["max_tokens", "temperature", "thinking", "output_config", "output_config.effort", "anthropic-version", "response_format"])
    func requiredControlsAndForeignFormatFieldsCannotBeDropped(_ field: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let error: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "code": "unsupported_parameter", "param": field]]
        environment.transport.respond(with: try JSONSerialization.data(withJSONObject: error), statusCode: 400)
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: .probe(.structured), schema: ReportPayload.schema))
            Issue.record("A required control was silently dropped")
        } catch { #expect(AIRequestError.reason(for: error) == .parameters) }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: [403, 404, 429])
    func bareStatusAndAmbiguousRequestErrorsPreserveUnknownEvidence(_ status: Int) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        environment.transport.respond(with: Data(#"{"error":{"message":"RAW_UNKNOWN_PRIVATE_30"}}"#.utf8), statusCode: status)
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint))
            Issue.record("A failed HTTP request was accepted")
        } catch { #expect(AIRequestError.reason(for: error) == (status == 429 ? .serviceLimit : .unknown)) }
    }

    @Test(arguments: ["adaptive thinking is not supported on this model",
                      "\"thinking.type.disabled\" is not supported for this model. Use adaptive thinking.",
                      "output_config.effort 'max' is not supported when thinking is disabled on this model.",
                      "temperature: Input should be less than or equal to 1",
                      "max_tokens: Input should be greater than 0",
                      "stream: Extra inputs are not permitted",
                      "output_config.format: Extra inputs are not permitted"], [false, true])
    func explicitNativeFieldRejectionsAreEvidenceWithoutRequiringARelayCode(_ message: String, _ streaming: Bool) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let error: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "message": message]]
        environment.transport.respond(with: streaming ? MessagesFixture.sse([error]) : try JSONSerialization.data(withJSONObject: error),
                                       statusCode: streaming ? 200 : 400)
        let optional: AIRequestError? = message.hasPrefix("stream:") ? .streamingUnsupported
            : message.hasPrefix("output_config.format:") ? .structuredUnsupported : nil
        let stage: AIProbeStage = optional == .streamingUnsupported ? .streaming : .structured
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: .probe(stage), schema: ReportPayload.schema, streaming: streaming))
            Issue.record("An explicitly rejected native field was accepted")
        } catch { #expect(AIRequestError.reason(for: error) == (optional ?? .parameters)) }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: ["authentication_error", "rate_limit_error", "overloaded_error", "timeout_error", "billing_error",
                      "permission_error", "not_found_error", "invalid_request_error"], [false, true])
    func nativeErrorsAreClassifiedWithoutInventingModelOrQuotaEvidence(_ type: String, _ streaming: Bool) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let error: [String: Any] = ["type": "error", "error": ["type": type, "message": "PRIVATE_RAW_ERROR_30"]]
        let data = streaming ? MessagesFixture.sse([error]) : try JSONSerialization.data(withJSONObject: error)
        environment.transport.respond(with: data, statusCode: streaming ? 200 : 400)
        let expected: AIRequestError
        switch type {
        case "authentication_error": expected = .authentication
        case "rate_limit_error": expected = .rateLimit
        case "overloaded_error": expected = .unavailable
        case "timeout_error": expected = .timeout
        case "billing_error": expected = .serviceLimit
        default: expected = .unknown
        }
        do {
            _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                .execute(messagesRequest(endpoint: environment.transport.endpoint, streaming: streaming))
            Issue.record("A native error was accepted")
        } catch { #expect(AIRequestError.reason(for: error) == expected) }
        #expect(environment.transport.requests.count == 1)
    }

    @Test(arguments: ["stream", "output_config.format", "output_config.format.schema"], ["unsupported_parameter", "unsupported_value"])
    func optionalRejectionsAreEvidenceOnlyForTheCorrespondingProbe(_ field: String, _ code: String) async throws {
        for intent in [AIRequestIntent.probe(field == "stream" ? .streaming : .structured), .composeReport, .extractFacts, .mergeFacts] {
            let environment = try IsolatedTestEnvironment(); defer { environment.close() }
            let error: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "code": code, "param": field,
                "message": "PRIVATE_RAW_ERROR_30"]]
            environment.transport.respond(with: try JSONSerialization.data(withJSONObject: error), statusCode: 400)
            let expected: AIRequestError
            if case .probe = intent { expected = field == "stream" ? .streamingUnsupported : .structuredUnsupported }
            else { expected = .parameters }
            do {
                _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
                    .execute(messagesRequest(endpoint: environment.transport.endpoint, intent: intent, schema: ReportPayload.schema, streaming: field == "stream"))
                Issue.record("A rejected parameter was accepted")
            } catch { #expect(AIRequestError.reason(for: error) == expected) }
            #expect(environment.transport.requests.count == 1)
        }
    }
}
