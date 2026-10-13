import Foundation
import Testing
@testable import random_thoughts

@Suite(.serialized)
@MainActor
struct ChatCompletionsHTTPTests {
    @Test(arguments: ["connection", "nonstreaming", "streaming"])
    func oneRequestTimesOutAtItsOwnPhaseDeadlineWithoutRetrying(_ phase: String) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let transport = AIHTTPTransport(configuration: .ephemeral, time: time)
        var request = URLRequest(url: server.endpoint); request.httpMethod = "POST"; request.httpBody = Data("synthetic".utf8)
        let operation = Task { try await transport.send(request, streaming: phase == "streaming") }
        _ = try await server.request()
        await environment.clock.waitForSleep(number: 1)
        if phase != "connection" {
            try server.headers()
            try server.write(Data(": connected\n\n".utf8))
            await environment.clock.waitForSleep(number: 2)
        }
        environment.clock.advance(by: phase == "connection" ? 31 : phase == "streaming" ? 91 : 301)
        do { _ = try await operation.value; Issue.record("Request did not time out") }
        catch { #expect(AIRequestError.reason(for: error) == .timeout) }
    }

    @Test func realHTTPPreservesEndpointAndDoesNotFollowRedirects() async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let access = ChatCompletionsAdapter(transport: .production())
        let request = makeRequest(endpoint: server.endpoint)
        let operation = Task { try await access.execute(request) }
        let wire = String(decoding: try await server.request(), as: UTF8.self)
        #expect(wire.hasPrefix("POST /complete?synthetic=28 HTTP/1.1\r\n"))
        #expect(wire.contains("Authorization: Bearer SYNTHETIC_HTTP_KEY_28"))
        try server.respond(Data(), status: 302, fields: ["Location": "http://127.0.0.1:9/forbidden"])
        do { _ = try await operation.value; Issue.record("Redirect was accepted") }
        catch { #expect(AIRequestError.reason(for: error) == .redirect) }
    }

    @Test func heartbeatsDoNotResetProgressButValidContentDoesAndStreamingHasNoFiveMinuteLimit() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let transport = AIHTTPTransport(configuration: .ephemeral, time: .init(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) }))
        let operation = Task { try await transport.send(URLRequest(url: server.endpoint), streaming: true) }
        _ = try await server.request(); await environment.clock.waitForSleep(number: 1)
        try server.headers(); try server.write(Data(": connected\n\n".utf8)); await environment.clock.waitForSleep(number: 2)
        for number in 3...7 {
            environment.clock.advance(by: 70)
            try server.write(Data((ChatCompletionsStreamTests.event(content: "合成", finish: nil) + "\n\n").utf8))
            await environment.clock.waitForSleep(number: number)
        }
        try server.write(Data(": heartbeat\n\n".utf8))
        environment.clock.advance(by: 91)
        do { _ = try await operation.value; Issue.record("Heartbeat extended the deadline") }
        catch { #expect(AIRequestError.reason(for: error) == .timeout) }
    }

    @Test func nativeSchemaAndCompleteSSEPassThroughTheRealHTTPAdapter() async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let base = makeRequest(endpoint: server.endpoint)
        let request = AIRequest(intent: .composeReport, configuration: base.configuration, credential: base.credential,
                                instruction: base.instruction, input: base.input, schema: ReportPayload.schema, streaming: true)
        let operation = Task { try await ChatCompletionsAdapter(transport: .production()).execute(request) }
        let raw = try await server.request()
        let marker = try #require(raw.range(of: Data("\r\n\r\n".utf8)))
        let json = try #require(try JSONSerialization.jsonObject(with: raw[marker.upperBound...]) as? [String: Any])
        #expect(json["store"] as? Bool == false && json["stream"] as? Bool == true)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect((schema["schema"] as? [String: Any])?["required"] as? [String] == ReportPayload.keys)
        let text = ChatCompletionsStreamTests.event(content: syntheticReportPayload, finish: "stop") + "\r\n\r\ndata: [DONE]\n\n"
        try server.respond(Data(text.utf8), fields: ["Content-Type": "text/event-stream"])
        #expect(try await operation.value == syntheticReportPayload)
    }

    @Test func aLegalStreamTerminatorCompletesWithoutWaitingForTheConnectionToClose() async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let base = makeRequest(endpoint: server.endpoint)
        let request = AIRequest(intent: .probe(.streaming), configuration: base.configuration, credential: base.credential,
                                instruction: base.instruction, input: base.input, schema: nil, streaming: true)
        let operation = Task { try await ChatCompletionsAdapter(transport: .production()).execute(request) }
        _ = try await server.request()
        try server.headers()
        try server.write(Data((ChatCompletionsStreamTests.event(content: "OK", finish: "stop") + "\n\ndata: [DONE]\n\n").utf8))
        // The server intentionally keeps the socket open after the legal SSE end.
        #expect(try await operation.value == "OK")
    }

    @Test func explicitRateLimitCarriesOnlyReliableWaitEvidence() async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let operation = Task { try await ChatCompletionsAdapter(transport: .production()).execute(makeRequest(endpoint: server.endpoint)) }
        _ = try await server.request()
        try server.respond(Data(#"{"error":{"code":"rate_limit_exceeded","message":"UNSAFE_RAW_ERROR_28"}}"#.utf8), status: 429, fields: ["Retry-After": "60"])
        do { _ = try await operation.value; Issue.record("Rate limit accepted") }
        catch {
            let failure = try #require(error as? AIRequestFailure)
            #expect(failure.reason == .rateLimit)
            #expect(try #require(failure.retryAt).timeIntervalSinceNow > 55)
        }
        #expect(AIHTTPTransport.retryDate("unknown", now: Date()) == nil)
        #expect(AIHTTPTransport.failure(status: 403, data: Data()) == .unknown)
        #expect(AIHTTPTransport.failure(status: 404, data: Data()) == .unknown)
        #expect(AIHTTPTransport.failure(status: 429, data: Data()) == .serviceLimit)
    }

    private func makeRequest(endpoint: URL) -> AIRequest {
        var configuration = AIServiceConfiguration(service: .chatCompletions)
        configuration.endpoint = endpoint.absoluteString; configuration.model = "synthetic"
        return .init(intent: .probe(.basic), configuration: configuration, credential: "SYNTHETIC_HTTP_KEY_28",
                     instruction: "Synthetic only", input: "OK", schema: nil, streaming: false)
    }
}
