import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct MessagesStreamTests {
    @Test func everyByteBoundaryPreservesUnicodeAndOnlyNativeEventsAdvanceTheStream() throws {
        let events = MessagesFixture.events("中文👩🏽‍💻 e\u{301}")
        var data = MessagesFixture.sse(Array(events.prefix(7)), newline: "\r\n", multiline: true)
        data.append(Data(": heartbeat\n\n".utf8))
        data.append(MessagesFixture.sse(Array(events.dropFirst(7)), newline: "\r", multiline: true))
        var parser = MessagesStream()
        #expect(try !parser.append(MessagesFixture.sse([["type": "ping"], ["type": "future_event"]])))
        for byte in data { _ = try parser.append(Data([byte])) }
        let result = try parser.finish()
        #expect(parser.hasTerminated)
        #expect(result.utf8.elementsEqual("中文👩🏽‍💻 e\u{301}".utf8))
    }

    @Test(arguments: ["missingStart", "duplicateStart", "missingSignature", "missingBlockStart", "missingBlockStop", "missingDelta",
                      "missingStop", "wrongIndex", "wrongDelta", "overlappingBlocks", "duplicateBlockStop", "lateDelta", "lateBlock",
                      "eventMismatch", "doneOnly", "refusal", "refusalDetails", "truncated", "tool", "empty"])
    func incompleteOrOutOfOrderEventsCannotProduceAReport(_ shape: String) {
        var events = MessagesFixture.events(shape == "empty" ? " \n" : "OK")
        switch shape {
        case "missingStart": events.removeFirst()
        case "duplicateStart": events.insert(events[0], at: 1)
        case "missingSignature": events.remove(at: 3)
        case "missingBlockStart": events.remove(at: 7)
        case "missingBlockStop": events.remove(at: 9)
        case "missingDelta": events.remove(at: 10)
        case "missingStop": events.removeLast()
        case "wrongIndex": events[8]["index"] = 1
        case "wrongDelta": events[8]["delta"] = ["type": "thinking_delta", "thinking": "NOT_TEXT_30"]
        case "overlappingBlocks": events.remove(at: 4)
        case "duplicateBlockStop": events.insert(events[9], at: 10)
        case "lateDelta": events.append(events[8])
        case "lateBlock": events.insert(events[7], at: 11)
        case "refusal": events[10]["delta"] = ["stop_reason": "refusal"]
        case "refusalDetails": events[10]["delta"] = ["stop_reason": "end_turn", "stop_details": ["type": "refusal"]]
        case "truncated": events[10]["delta"] = ["stop_reason": "max_tokens"]
        case "tool": events[7]["content_block"] = ["type": "tool_use", "id": "tool_30", "name": "synthetic", "input": [:]]
        default: break
        }
        var data = MessagesFixture.sse(events)
        if shape == "eventMismatch" {
            data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "event: content_block_delta", with: "event: message_delta").utf8)
        }
        if shape == "doneOnly" { data = Data("data: [DONE]\n\n".utf8) }
        #expect(throws: (any Error).self) {
            var parser = MessagesStream(); _ = try parser.append(data); _ = try parser.finish()
        }
    }

    @Test func usageOnlyMessageDeltasDoNotSubstituteForACompleteStopReason() throws {
        var events = MessagesFixture.events("OK")
        let usage: [String: Any] = ["type": "message_delta", "delta": ["stop_reason": NSNull()], "usage": ["output_tokens": 12]]
        events.insert(usage, at: 10); events.insert(usage, at: 12)
        var parser = MessagesStream()
        _ = try parser.append(MessagesFixture.sse(events))
        #expect(try parser.finish() == "OK")
    }

    @Test func nativeThinkingAndTextBlocksCompleteThroughTheMessagesStream() async throws {
        let environment = try IsolatedTestEnvironment(); defer { environment.close() }
        let text = "中文👩🏽‍💻 e\u{301} 合成完成"
        environment.transport.respond(with: MessagesFixture.sse(MessagesFixture.events(text), newline: "\r\n", multiline: true))
        let result = try await AIServiceClient(transport: .init(configuration: environment.transport.session.configuration, time: .production))
            .execute(messagesRequest(endpoint: environment.transport.endpoint, streaming: true))
        #expect(result.utf8.elementsEqual(text.utf8))
    }
}
