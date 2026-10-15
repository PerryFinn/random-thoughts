import Foundation
import Testing
@testable import random_thoughts

struct ResponsesStreamTests {
    @Test func heartbeatsAndUnknownEventsDoNotCountAsEffectiveProgress() throws {
        let events = ResponsesFixture.events("OK")
        var parser = ResponsesStream()
        #expect(try parser.append(ResponsesFixture.sse(Array(events.prefix(6)))))
        #expect(try !parser.append(Data(": heartbeat\n\n".utf8)))
        #expect(try !parser.append(ResponsesFixture.sse([["type": "response.future_event", "sequence_number": 6]])))
        let remaining = events.dropFirst(6).map { event in
            event.merging(["sequence_number": (event["sequence_number"] as! Int) + 1]) { _, new in new }
        }
        #expect(try parser.append(ResponsesFixture.sse(remaining)))
        #expect(try parser.finish() == "OK")
    }

    @Test(arguments: ["missingCreated", "missingPart", "missingTextDone", "missingPartDone", "missingItemDone", "missingCompleted",
                      "duplicateSequence", "wrongItem", "wrongOutput", "wrongContent", "terminalMismatch", "wrongResponse",
                      "refusal", "incomplete", "tool", "lateText", "doneOnly", "eventMismatch"])
    func incompleteOrInconsistentNativeEventsCannotBecomeReports(_ shape: String) {
        var events = ResponsesFixture.events("OK")
        switch shape {
        case "missingCreated": events.removeFirst()
        case "missingPart": events.remove(at: 5)
        case "missingTextDone": events.remove(at: 7)
        case "missingPartDone": events.remove(at: 8)
        case "missingItemDone": events.remove(at: 9)
        case "missingCompleted": events.removeLast()
        case "duplicateSequence": events[6]["sequence_number"] = 5
        case "wrongItem": events[6]["item_id"] = "msg_other"
        case "wrongOutput": events[6]["output_index"] = 0
        case "wrongContent": events[6]["content_index"] = 1
        case "terminalMismatch": events[10]["response"] = ResponsesFixture.response("different text")
        case "wrongResponse":
            var response = ResponsesFixture.response("OK"); response["id"] = "resp_other"; events[10]["response"] = response
        case "refusal": events[6]["type"] = "response.refusal.delta"
        case "incomplete":
            events[10]["type"] = "response.incomplete"; events[10]["response"] = ResponsesFixture.response("OK", status: "incomplete")
        case "tool": events[4]["item"] = ["id": "tool_29", "type": "function_call", "status": "in_progress"]
        case "lateText": events.append(["type": "response.output_text.delta", "sequence_number": 11, "delta": "late"])
        default: break
        }
        var data = ResponsesFixture.sse(events)
        if shape == "doneOnly" { data = Data("data: [DONE]\n\n".utf8) }
        if shape == "eventMismatch" {
            data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "event: response.output_text.delta", with: "event: response.completed").utf8)
        }
        #expect(throws: (any Error).self) {
            var parser = ResponsesStream(); _ = try parser.append(data); _ = try parser.finish()
        }
    }

    @Test func anErrorForAnotherResponseCannotInvalidateThisConfigurationsQualification() throws {
        var events = Array(ResponsesFixture.events("OK").prefix(1))
        var failed = ResponsesFixture.response("", status: "failed")
        failed["id"] = "resp_other_29"; failed["error"] = ["code": "invalid_api_key"]
        events.append(["type": "response.failed", "sequence_number": 1, "response": failed])
        #expect(throws: AIRequestError.invalidResponse) {
            var parser = ResponsesStream(); _ = try parser.append(ResponsesFixture.sse(events)); _ = try parser.finish()
        }
    }

    @Test func nativeEventsAtEveryByteBoundaryPreserveUnicodeAndFinishAtTheCompletedResponse() throws {
        let text = "中文👩🏽‍💻 e\u{301} 合成完成"
        let events = ResponsesFixture.events(text)
        var data = ResponsesFixture.sse(Array(events.prefix(5)), newline: "\r\n", multiline: true)
        data.append(Data(": heartbeat\n\n".utf8))
        data.append(ResponsesFixture.sse(Array(events.dropFirst(5)), newline: "\r", multiline: true))
        var parser = ResponsesStream()
        for byte in data { _ = try parser.append(Data([byte])) }
        #expect(try parser.finish() == text)
        #expect(parser.hasTerminated)
    }
}
