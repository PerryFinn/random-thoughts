import Foundation
@testable import random_thoughts

// Entirely synthetic native Messages objects; reference contract read 2026-10-15.
enum MessagesFixture {
    static func message(_ text: String, stop: String? = "end_turn") -> [String: Any] {
        ["id": "msg_synthetic_30", "type": "message", "role": "assistant", "model": "synthetic-messages-30",
         "content": [["type": "text", "text": text]], "stop_reason": stop as Any? ?? NSNull(),
         "stop_sequence": NSNull(), "usage": ["input_tokens": 12, "output_tokens": 8]]
    }
    static func completion(_ text: String) -> Data { try! JSONSerialization.data(withJSONObject: message(text)) }
    static func events(_ text: String) -> [[String: Any]] {
        var opening = message("", stop: nil); opening["content"] = []
        return [
            ["type": "message_start", "message": opening],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "PRIVATE_THINKING_30"]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "PRIVATE_SIGNATURE_30"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "redacted_thinking", "data": "PRIVATE_REDACTED_30"]],
            ["type": "content_block_stop", "index": 1],
            ["type": "content_block_start", "index": 2, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 2, "delta": ["type": "text_delta", "text": text]],
            ["type": "content_block_stop", "index": 2],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()], "usage": ["output_tokens": 24]],
            ["type": "message_stop"]
        ]
    }
    static func sse(_ events: [[String: Any]], newline: String = "\n", multiline: Bool = false) -> Data {
        Data(events.map { event in
            let json = try! JSONSerialization.data(withJSONObject: event, options: multiline ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
            let data = String(decoding: json, as: UTF8.self).components(separatedBy: "\n").map { "data: " + $0 }
            return (["event: " + (event["type"] as! String)] + data).joined(separator: newline) + newline + newline
        }.joined().utf8)
    }
}

func messagesRequest(endpoint: URL, intent: AIRequestIntent = .probe(.basic), schema: String? = nil,
                     streaming: Bool = false, defaults: MessagesDefaults = .init()) -> AIRequest {
    var configuration = AIServiceConfiguration(service: .messages)
    configuration.endpoint = endpoint.absoluteString; configuration.model = "synthetic-messages-30"
    configuration.defaults = .messages(defaults); configuration.outputLimit = 4_096
    return .init(intent: intent, configuration: configuration, credential: "SYNTHETIC_MESSAGES_KEY_30",
                 instruction: "Synthetic system", input: "Synthetic user", schema: schema, streaming: streaming)
}
