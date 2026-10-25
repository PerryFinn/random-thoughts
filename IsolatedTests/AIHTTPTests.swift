import Foundation
import Testing
@testable import random_thoughts

@Suite(.serialized)
@MainActor
struct AIHTTPTests {
    @Test func evenCacheableGETResponsesCannotPopulateAnInjectedDiskCache() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let cache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 1_048_576,
            directory: environment.directory.appendingPathComponent("request-cache"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = cache
        let access = AIHTTPTransport(configuration: configuration, time: .production)
        let lookup = URLRequest(url: server.endpoint)
        let operation = Task { try await access.send(lookup, stream: nil, service: .chatCompletions) }
        _ = try await server.request()
        let response = completion("CACHE_RESPONSE_PRIVATE_34")
        try server.respond(response, fields: ["Cache-Control": "public, max-age=3600", "Content-Location": server.endpoint.absoluteString])
        #expect(try await operation.value == response)
        #expect(cache.cachedResponse(for: lookup) == nil)
        #expect(cache.currentMemoryUsage == 0 && cache.currentDiskUsage == 0)
        #expect(configuration.urlCache === cache)
    }

    @Test(arguments: AIServiceType.allCases)
    func nonstreamingErrorObjectsPreserveReliableWaitEvidence(_ service: AIServiceType) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let operation = Task { try await AIServiceClient(transport: .init(configuration: .ephemeral, time: time))
            .execute(makeRequest(endpoint: server.endpoint, service: service)) }
        _ = try await server.request()
        var value: [String: Any] = service == .responses ? ResponsesFixture.response("", status: "failed") : [:]
        value["error"] = service == .messages
            ? ["type": "rate_limit_error", "message": "RAW_PRIVATE_ERROR_32"]
            : ["code": "rate_limit_exceeded", "message": "RAW_PRIVATE_ERROR_32"]
        try server.respond(JSONSerialization.data(withJSONObject: value), fields: ["Retry-After": "60"])
        do { _ = try await operation.value; Issue.record("A nonstreaming rate limit was accepted") }
        catch {
            #expect(AIRequestError.reason(for: error) == .rateLimit)
            #expect((error as? AIRequestFailure)?.retryAt == Date(timeIntervalSince1970: 1_060))
        }
    }

    @Test(arguments: AIServiceType.allCases)
    func inBandRateLimitsKeepReliableWaitEvidenceWithoutWaitingForSocketClosure(_ service: AIServiceType) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let base = makeRequest(endpoint: server.endpoint, service: service)
        let request = AIRequest(intent: .composeReport, configuration: base.configuration, credential: base.credential,
            instruction: base.instruction, input: base.input, schema: nil, streaming: true)
        let operation = Task { try await AIServiceClient(transport: .init(configuration: .ephemeral, time: time)).execute(request) }
        _ = try await server.request(); await environment.clock.waitForSleep(number: 1)
        try server.headers(fields: ["Retry-After": "60"])
        try server.write(Data(": connected\n\n".utf8)); await environment.clock.waitForSleep(number: 2)
        environment.clock.advance(by: 10)
        let payload: Data
        switch service {
        case .chatCompletions:
            payload = Data("data: {\"error\":{\"code\":\"rate_limit_exceeded\",\"message\":\"RAW_PRIVATE_ERROR_32\"}}\n\n".utf8)
        case .responses:
            payload = ResponsesFixture.sse([["type": "error", "sequence_number": 0, "code": "rate_limit_exceeded", "message": "RAW_PRIVATE_ERROR_32"]])
        case .messages:
            payload = MessagesFixture.sse([["type": "error", "error": ["type": "rate_limit_error", "message": "RAW_PRIVATE_ERROR_32"]]])
        }
        try server.write(payload)
        do { _ = try await operation.value; Issue.record("An in-band rate limit was accepted") }
        catch {
            #expect(AIRequestError.reason(for: error) == .rateLimit)
            #expect((error as? AIRequestFailure)?.retryAt == Date(timeIntervalSince1970: 1_060))
        }
    }

    @Test(arguments: ["connection", "nonstreaming", "streaming"], AIServiceType.allCases)
    func elapsedSleepTimeRejectsALateResponseEvenBeforeTheWatchdogResumes(_ phase: String, _ service: AIServiceType) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let parser: (any AIResponseStream)?
        if phase != "streaming" { parser = nil }
        else {
            parser = switch service {
            case .chatCompletions: ChatCompletionsStream()
            case .responses: ResponsesStream()
            case .messages: MessagesStream()
            }
        }
        let operation = Task { try await AIHTTPTransport(configuration: .ephemeral, time: time)
            .send(URLRequest(url: server.endpoint), stream: parser, service: service) }
        _ = try await server.request(); await environment.clock.waitForSleep(number: 1)
        if phase != "connection" {
            try server.headers(); try server.write(Data(": connected\n\n".utf8))
            await environment.clock.waitForSleep(number: 2)
        }
        environment.clock.elapseWithoutScheduling(by: phase == "connection" ? 30 : phase == "streaming" ? 90 : 300)
        if phase == "connection" { try server.headers() }
        try server.write(Data("LATE_RESPONSE_AFTER_WAKE_32\n\n".utf8))
        do { _ = try await operation.value; Issue.record("A response after the deadline was accepted") }
        catch { #expect(AIRequestError.reason(for: error) == .timeout) }
    }

    @Test(arguments: [false, true])
    func messagesPreservesItsFullRouteAndNativeHeadersOverRealHTTP(_ streaming: Bool) async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        var endpoint = URLComponents(url: server.endpoint, resolvingAgainstBaseURL: false)!
        endpoint.path = "/custom/messages/"; endpoint.percentEncodedQuery = "synthetic=30%2Fprobe&order=1"
        let request = messagesRequest(endpoint: endpoint.url!, intent: .composeReport, schema: ReportPayload.schema,
            streaming: streaming, defaults: .init(temperature: 0, thinking: .adaptive, effort: .high))
        let operation = Task { try await AIServiceClient(transport: .production()).execute(request) }
        let raw = try await server.request(), wire = String(decoding: raw, as: UTF8.self)
        #expect(wire.hasPrefix("POST /custom/messages/?synthetic=30%2Fprobe&order=1 HTTP/1.1\r\n"))
        #expect(wire.lowercased().contains("x-api-key: synthetic_messages_key_30"))
        #expect(wire.lowercased().contains("anthropic-version: 2023-06-01") && !wire.lowercased().contains("authorization:"))
        let marker = try #require(raw.range(of: Data("\r\n\r\n".utf8)))
        let object = try #require(try JSONSerialization.jsonObject(with: raw[marker.upperBound...]) as? [String: Any])
        #expect(object["max_tokens"] as? Int == 4_096 && object["stream"] as? Bool == streaming)
        #expect((object["output_config"] as? [String: Any])?["format"] != nil)
        #expect(object["store"] == nil && object["truncation"] == nil && object["response_format"] == nil)
        let data = streaming ? MessagesFixture.sse(MessagesFixture.events(syntheticReportPayload)) : MessagesFixture.completion(syntheticReportPayload)
        try server.respond(data)
        #expect(try await operation.value == syntheticReportPayload)
    }

    @Test func messagesThinkingIsEffectiveProgressBeyondFiveMinutesAndStopsWithoutSocketClosure() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let access = AIServiceClient(transport: .init(configuration: .ephemeral, time: time))
        let operation = Task { try await access.execute(messagesRequest(endpoint: server.endpoint, streaming: true)) }
        _ = try await server.request(); await environment.clock.waitForSleep(number: 1)
        try server.headers(); try server.write(Data(": connected\n\n".utf8)); await environment.clock.waitForSleep(number: 2)
        let events = MessagesFixture.events("OK")
        try server.write(MessagesFixture.sse(Array(events.prefix(2))))
        await environment.clock.waitForSleep(number: 3)
        for index in 0..<5 {
            environment.clock.advance(by: 70)
            try server.write(MessagesFixture.sse([events[2]]))
            await environment.clock.waitForSleep(number: 4 + index)
        }
        try server.write(MessagesFixture.sse(Array(events.dropFirst(3))))
        #expect(try await operation.value == "OK")
    }

    @Test(arguments: AIServiceType.allCases)
    func cancellingHTTPImmediatelyFinishesWithoutAcceptingALateTerminalEvent(_ service: AIServiceType) async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let base = makeRequest(endpoint: server.endpoint, service: service)
        let request = AIRequest(intent: .probe(.streaming), configuration: base.configuration, credential: base.credential,
            instruction: base.instruction, input: base.input, schema: nil, streaming: true)
        let operation = Task { try await AIServiceClient(transport: .production()).execute(request) }
        _ = try await server.request()
        try server.headers(); try server.write(Data(": connected\n\n".utf8))
        operation.cancel()
        do { _ = try await operation.value; Issue.record("Cancellation accepted a response") }
        catch { #expect(AIRequestError.reason(for: error) == .cancelled) }
        try? server.write(Data("data: LATE_TERMINAL_30\n\n".utf8))
    }

    @Test func responsesValidProgressCanRunBeyondFiveMinutesAndFinishWithTheSocketStillOpen() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let adapter = ResponsesAdapter(transport: .init(configuration: .ephemeral, time: time))
        let operation = Task { try await adapter.execute(responsesRequest(endpoint: server.endpoint, streaming: true)) }
        _ = try await server.request(); await environment.clock.waitForSleep(number: 1)
        try server.headers(); try server.write(Data(": connected\n\n".utf8)); await environment.clock.waitForSleep(number: 2)
        let events = ResponsesFixture.events(String(repeating: "合成", count: 5))
        try server.write(ResponsesFixture.sse(Array(events.prefix(6))))
        await environment.clock.waitForSleep(number: 3)
        for index in 0..<5 {
            environment.clock.advance(by: 70)
            var delta = events[6]; delta["delta"] = "合成"; delta["sequence_number"] = 6 + index
            try server.write(ResponsesFixture.sse([delta]))
            await environment.clock.waitForSleep(number: 4 + index)
        }
        let ending = events.dropFirst(7).enumerated().map { index, event in
            event.merging(["sequence_number": 11 + index]) { _, new in new }
        }
        try server.write(ResponsesFixture.sse(ending))
        #expect(try await operation.value == String(repeating: "合成", count: 5))
    }

    @Test func responsesSSEUsesItsNativeEventsAndPreservesTheCompleteHTTPRoute() async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        var endpoint = URLComponents(url: server.endpoint, resolvingAgainstBaseURL: false)!
        endpoint.path = "/custom/responses/"; endpoint.percentEncodedQuery = "synthetic=29%2Fprobe&order=1"
        var configuration = AIServiceConfiguration(service: .responses)
        configuration.endpoint = endpoint.url!.absoluteString; configuration.model = "synthetic-responses-29"
        let operation = Task { try await ResponsesAdapter(transport: .production()).execute(.init(intent: .composeReport,
            configuration: configuration, credential: "SYNTHETIC_HTTP_KEY_29", instruction: "Synthetic only", input: "Probe",
            schema: ReportPayload.schema, streaming: true)) }
        let raw = try await server.request()
        let wire = String(decoding: raw, as: UTF8.self)
        #expect(wire.hasPrefix("POST /custom/responses/?synthetic=29%2Fprobe&order=1 HTTP/1.1\r\n"))
        #expect(wire.contains("Authorization: Bearer SYNTHETIC_HTTP_KEY_29"))
        let marker = try #require(raw.range(of: Data("\r\n\r\n".utf8)))
        let json = try #require(try JSONSerialization.jsonObject(with: raw[marker.upperBound...]) as? [String: Any])
        #expect(json["stream"] as? Bool == true && json["truncation"] as? String == "disabled")
        #expect((json["text"] as? [String: Any])?["format"] != nil && json["messages"] == nil)
        try server.respond(ResponsesFixture.sse(ResponsesFixture.events(syntheticReportPayload)), fields: ["Content-Type": "text/event-stream"])
        #expect(try await operation.value == syntheticReportPayload)
    }

    @Test(arguments: ["connection", "nonstreaming", "streaming"], AIServiceType.allCases)
    func oneRequestTimesOutAtItsOwnPhaseDeadlineWithoutRetrying(_ phase: String, _ service: AIServiceType) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let time = AITransportTime(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) })
        let transport = AIHTTPTransport(configuration: .ephemeral, time: time)
        var request = URLRequest(url: server.endpoint); request.httpMethod = "POST"; request.httpBody = Data("synthetic".utf8)
        let parser: (any AIResponseStream)?
        if phase != "streaming" { parser = nil }
        else {
            parser = switch service {
            case .chatCompletions: ChatCompletionsStream()
            case .responses: ResponsesStream()
            case .messages: MessagesStream()
            }
        }
        let operation = Task { try await transport.send(request, stream: parser, service: service) }
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

    @Test(arguments: AIServiceType.allCases)
    func realHTTPPreservesEndpointAndDoesNotFollowRedirects(_ service: AIServiceType) async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let access = AIServiceClient(transport: .production())
        let request = makeRequest(endpoint: server.endpoint, service: service)
        let operation = Task { try await access.execute(request) }
        let wire = String(decoding: try await server.request(), as: UTF8.self)
        #expect(wire.hasPrefix("POST /complete?synthetic=28 HTTP/1.1\r\n"))
        if service == .messages { #expect(wire.lowercased().contains("x-api-key: \(request.credential.lowercased())")) }
        else { #expect(wire.contains("Authorization: Bearer \(request.credential)")) }
        try server.respond(Data(), status: 302, fields: ["Location": "http://127.0.0.1:9/forbidden"])
        do { _ = try await operation.value; Issue.record("Redirect was accepted") }
        catch { #expect(AIRequestError.reason(for: error) == .redirect) }
    }

    @Test func heartbeatsDoNotResetProgressButValidContentDoesAndStreamingHasNoFiveMinuteLimit() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let server = try LoopbackChatServer(); defer { server.close() }
        let transport = AIHTTPTransport(configuration: .ephemeral, time: .init(now: { await environment.clock.now }, sleep: { try await environment.clock.sleep(for: $0) }))
        let operation = Task { try await transport.send(URLRequest(url: server.endpoint), stream: ChatCompletionsStream(), service: .chatCompletions) }
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

    @Test(arguments: AIServiceType.allCases)
    func aLegalStreamTerminatorCompletesWithoutWaitingForTheConnectionToClose(_ service: AIServiceType) async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let base = makeRequest(endpoint: server.endpoint, service: service)
        let request = AIRequest(intent: .probe(.streaming), configuration: base.configuration, credential: base.credential,
                                instruction: base.instruction, input: base.input, schema: nil, streaming: true)
        let operation = Task { try await AIServiceClient(transport: .production()).execute(request) }
        _ = try await server.request()
        try server.headers()
        let data: Data
        switch service {
        case .chatCompletions: data = Data((ChatCompletionsStreamTests.event(content: "OK", finish: "stop") + "\n\ndata: [DONE]\n\n").utf8)
        case .responses: data = ResponsesFixture.sse(ResponsesFixture.events("OK"))
        case .messages: data = MessagesFixture.sse(MessagesFixture.events("OK"))
        }
        try server.write(data)
        // The server intentionally keeps the socket open after the legal SSE end.
        #expect(try await operation.value == "OK")
    }

    @Test(arguments: AIServiceType.allCases)
    func explicitRateLimitCarriesOnlyReliableWaitEvidence(_ service: AIServiceType) async throws {
        let server = try LoopbackChatServer(); defer { server.close() }
        let operation = Task { try await AIServiceClient(transport: .production()).execute(makeRequest(endpoint: server.endpoint, service: service)) }
        _ = try await server.request()
        let error: [String: Any] = ["error": ["type": service == .messages ? "rate_limit_error" : "rate_limit_exceeded", "message": "UNSAFE_RAW_ERROR_30"]]
        try server.respond(try JSONSerialization.data(withJSONObject: error), status: 429, fields: ["Retry-After": "60"])
        do { _ = try await operation.value; Issue.record("Rate limit accepted") }
        catch {
            let failure = try #require(error as? AIRequestFailure)
            #expect(failure.reason == .rateLimit)
            #expect(try #require(failure.retryAt).timeIntervalSinceNow > 55)
        }
        #expect(AIHTTPTransport.retryDate("unknown", now: Date()) == nil)
        #expect(AIHTTPTransport.failure(status: 403, data: Data(), service: .chatCompletions) == .unknown)
        #expect(AIHTTPTransport.failure(status: 404, data: Data(), service: .chatCompletions) == .unknown)
        #expect(AIHTTPTransport.failure(status: 429, data: Data(), service: .chatCompletions) == .serviceLimit)
    }

    private func makeRequest(endpoint: URL, service: AIServiceType = .chatCompletions) -> AIRequest {
        if service == .responses { return responsesRequest(endpoint: endpoint) }
        if service == .messages { return messagesRequest(endpoint: endpoint) }
        var configuration = AIServiceConfiguration(service: .chatCompletions)
        configuration.endpoint = endpoint.absoluteString; configuration.model = "synthetic"
        return .init(intent: .probe(.basic), configuration: configuration, credential: "SYNTHETIC_HTTP_KEY_28",
                     instruction: "Synthetic only", input: "OK", schema: nil, streaming: false)
    }
}
