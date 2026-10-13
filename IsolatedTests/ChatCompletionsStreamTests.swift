import Foundation
import Testing
@testable import random_thoughts

struct ChatCompletionsStreamTests {
    @Test func nullOptionalCallsAreAbsentButNonTextContentCannotBeIgnored() throws {
        let valid = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\",\"tool_calls\":null,\"function_call\":null},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        var parser = ChatCompletionsStream(); _ = try parser.append(Data(valid.utf8))
        #expect(try parser.finish() == "OK")
        let invalid = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":[\"unexpected\"]},\"finish_reason\":null}]}\n\n" + valid
        #expect(throws: (any Error).self) {
            var parser = ChatCompletionsStream(); _ = try parser.append(Data(invalid.utf8)); _ = try parser.finish()
        }
    }
    @Test func mixedLineEndingsAndEveryByteBoundaryPreserveUnicodeAndRequireCompletion() throws {
        let first = event(content: "中文👩🏽‍💻", finish: nil) + "\r\n\r\n"
        let second = event(content: "完成", finish: "stop") + "\n\n"
        let fixture = Data((first + second + "data: [DONE]\r\r").utf8)
        var parser = ChatCompletionsStream()
        for byte in fixture { _ = try parser.append(Data([byte])) }
        #expect(try parser.finish() == "中文👩🏽‍💻完成")
    }

    @Test(arguments: ["missingDone", "missingStop", "length", "refusal", "wrongIndex", "lateText"])
    func incompleteOrRefusedStreamsCannotBecomeReports(_ shape: String) {
        var text = event(content: "synthetic", finish: shape == "length" ? "length" : shape == "missingStop" ? nil : "stop") + "\n\n"
        if shape == "refusal" { text = "data: {\"choices\":[{\"index\":0,\"delta\":{\"refusal\":\"refused\"},\"finish_reason\":\"stop\"}]}\n\n" }
        if shape == "wrongIndex" { text = text.replacingOccurrences(of: "\"index\":0", with: "\"index\":1") }
        if shape != "missingDone" { text += "data: [DONE]\n\n" }
        if shape == "lateText" { text += event(content: "late", finish: nil) + "\n\n" }
        #expect(throws: (any Error).self) {
            var parser = ChatCompletionsStream(); _ = try parser.append(Data(text.utf8)); _ = try parser.finish()
        }
    }

    static func event(content: String, finish: String?) -> String {
        let value: [String: Any] = ["id": "synthetic", "choices": [["index": 0, "delta": ["content": content], "finish_reason": finish as Any? ?? NSNull()]]]
        return "data: " + String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    private func event(content: String, finish: String?) -> String { Self.event(content: content, finish: finish) }
}
