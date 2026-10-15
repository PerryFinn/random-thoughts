import Foundation

// Synthetic native HTTP/SSE objects based on the Responses reference, 2026-10-15.
enum ResponsesFixture {
    static func response(_ text: String, status: String = "completed") -> [String: Any] {
        ["id": "resp_synthetic_29", "object": "response", "status": status, "error": NSNull(), "incomplete_details": NSNull(),
         "output": [reasoning(status: "completed"), message(text, status: "completed")]]
    }
    static func part(_ text: String) -> [String: Any] { ["type": "output_text", "text": text, "annotations": [], "logprobs": []] }
    static func message(_ text: String, status: String) -> [String: Any] {
        ["type": "message", "id": "msg_synthetic_29", "role": "assistant", "status": status,
         "content": status == "in_progress" ? [] : [part(text)]]
    }
    static func reasoning(status: String) -> [String: Any] {
        ["id": "rs_synthetic_29", "type": "reasoning", "status": status, "summary": []]
    }
    static func events(_ text: String) -> [[String: Any]] {
        var opening = response("", status: "in_progress"); opening["output"] = []
        let address: [String: Any] = ["item_id": "msg_synthetic_29", "output_index": 1, "content_index": 0]
        func content(_ type: String, _ fields: [String: Any]) -> [String: Any] {
            address.merging(["type": type]) { _, new in new }.merging(fields) { _, new in new }
        }
        let events: [[String: Any]] = [
            ["type": "response.created", "response": opening],
            ["type": "response.in_progress", "response": opening],
            ["type": "response.output_item.added", "output_index": 0, "item": reasoning(status: "in_progress")],
            ["type": "response.output_item.done", "output_index": 0, "item": reasoning(status: "completed")],
            ["type": "response.output_item.added", "output_index": 1, "item": message("", status: "in_progress")],
            content("response.content_part.added", ["part": part("")]),
            content("response.output_text.delta", ["delta": text]),
            content("response.output_text.done", ["text": text]),
            content("response.content_part.done", ["part": part(text)]),
            ["type": "response.output_item.done", "output_index": 1, "item": message(text, status: "completed")],
            ["type": "response.completed", "response": response(text)]
        ]
        return events.enumerated().map { $0.element.merging(["sequence_number": $0.offset]) { _, new in new } }
    }
    static func sse(_ events: [[String: Any]], newline: String = "\n", multiline: Bool = false) -> Data {
        Data(events.map { event in
            let data = try! JSONSerialization.data(withJSONObject: event, options: multiline ? [.sortedKeys, .prettyPrinted] : [.sortedKeys])
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").map { "data: " + $0 }
            return (["event: " + (event["type"] as! String)] + lines).joined(separator: newline) + newline + newline
        }.joined().utf8)
    }
}
