import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct ReportBatchWireTests {
    @Test(arguments: AIServiceType.allCases)
    func everyProtocolPreservesIndependentSummaryBlocksAndItsOwnControls(_ service: AIServiceType) async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        switch service {
        case .chatCompletions: environment.transport.respond(with: completion("OK"))
        case .responses: environment.transport.respond(with: try JSONSerialization.data(withJSONObject: ResponsesFixture.response("OK")))
        case .messages: environment.transport.respond(with: MessagesFixture.completion("OK"))
        }
        var configuration = AIServiceConfiguration(service: service)
        configuration.endpoint = environment.transport.endpoint.absoluteString
        configuration.model = "synthetic-batch"; configuration.outputLimit = 3_000
        let blocks = [#"{"id":1,"facts":["👩🏽‍💻é\\\""],"noRelevantContent":false}"#, #"{"id":2,"facts":[],"noRelevantContent":true}"#]
        let request = AIRequest(intent: .mergeFacts, configuration: configuration, credential: "synthetic",
            instruction: "Synthetic fact contract", input: "Synthetic metadata", schema: ReportFactPayload.schema,
            streaming: false, additionalInputs: blocks)
        _ = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production)).execute(request)
        let sent = try #require(environment.transport.requests.first)
        let object = try JSONSerialization.jsonObject(with: body(of: sent)) as! [String: Any]
        let content: [[String: Any]]
        switch service {
        case .chatCompletions:
            content = (object["messages"] as! [[String: Any]])[1]["content"] as! [[String: Any]]
            #expect(object["max_completion_tokens"] as? Int == 3_000 && object["store"] as? Bool == false)
        case .responses:
            content = (object["input"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
            #expect(object["max_output_tokens"] as? Int == 3_000 && object["truncation"] as? String == "disabled")
        case .messages:
            content = (object["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
            #expect(object["max_tokens"] as? Int == 3_000 && object["store"] == nil)
        }
        #expect(content.compactMap { $0["text"] as? String } == [request.input] + blocks)
        #expect(content.allSatisfy { $0["type"] as? String == (service == .responses ? "input_text" : "text") })
        #expect(environment.transport.requests.count == 1)
    }
}
