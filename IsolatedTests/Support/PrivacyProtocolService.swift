import Foundation
@testable import random_thoughts

// Serial synthetic response producer around the REAL protocol client. Privacy
// scenarios configure concurrency=1; scheduling/concurrency has its own tests.
actor PrivacyProtocolService {
    private let transport: SyntheticTransport
    private let client: AIServiceClient
    private let facts = BatchAIService(mode: .dense)
    private let streamingSupported: Bool
    private var failsNext = false
    private(set) var requests: [AIRequest] = []

    init(transport: SyntheticTransport, streamingSupported: Bool) {
        self.transport = transport
        self.streamingSupported = streamingSupported
        client = AIServiceClient(transport: .init(configuration: transport.session.configuration, time: .production))
    }

    func failNext() { failsNext = true }

    func execute(_ request: AIRequest) async throws -> String {
        requests.append(request)
        if failsNext {
            failsNext = false
            transport.enqueue(Data(#"{"error":{"type":"api_error","code":"server_error","message":"RAW_ERROR_PRIVATE_34"}}"#.utf8), statusCode: 503)
        } else if case .probe(.streaming) = request.intent, !streamingSupported {
            transport.enqueue(Data(#"{"error":{"type":"invalid_request_error","code":"unsupported_parameter","param":"stream","message":"RAW_OPTIONAL_ERROR_PRIVATE_34"}}"#.utf8), statusCode: 400)
        } else {
            var text = try await facts.execute(request)
            switch request.intent {
            case .composeReport:
                text = text.replacingOccurrences(of: "合成进展", with: "RESULT_PRIVATE_34 \(request.credential)")
            case .extractFacts, .mergeFacts:
                var payload = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
                var entries = payload["facts"] as! [[String: Any]]
                for index in entries.indices {
                    entries[index]["summary"] = "INTERMEDIATE_PRIVATE_34 \(request.credential) " + (entries[index]["summary"] as! String)
                }
                payload["facts"] = entries
                text = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
            case .probe: break
            }
            let data: Data
            switch request.configuration.service {
            case .chatCompletions:
                data = request.streaming
                    ? Data((ChatCompletionsStreamTests.event(content: text, finish: "stop") + "\n\ndata: [DONE]\n\n").utf8)
                    : completion(text)
            case .responses:
                data = request.streaming ? ResponsesFixture.sse(ResponsesFixture.events(text)) : responsesCompletion(text)
            case .messages:
                data = request.streaming ? MessagesFixture.sse(MessagesFixture.events(text)) : MessagesFixture.completion(text)
            }
            transport.enqueue(data)
        }
        return try await client.execute(request)
    }
}

extension PrivacyProtocolService: AIServiceAccess {}
