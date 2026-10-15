import Foundation

nonisolated struct ChatCompletionsStream: AIResponseStream {
    private var framing = ServerSentEvents()
    private var text = ""
    private var finished = false
    private var done = false
    private var identifier: String?
    var hasTerminated: Bool { done }

    mutating func append(_ data: Data) throws -> Bool {
        var progressed = false
        for event in try framing.append(data) { progressed = try consume(event.data) || progressed }
        return progressed
    }
    mutating func finish() throws -> String {
        for event in try framing.finish() { _ = try consume(event.data) }
        guard done, finished,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.incomplete }
        return text
    }
    private mutating func consume(_ payload: String) throws -> Bool {
        if payload.isEmpty { return false }
        guard !done else { throw AIRequestError.invalidResponse }
        if payload == "[DONE]" { guard finished else { throw AIRequestError.incomplete }; done = true; return true }
        guard let value = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let choices = value["choices"] as? [[String: Any]] else { throw AIRequestError.invalidResponse }
        if let id = value["id"] as? String {
            if let identifier, identifier != id { throw AIRequestError.invalidResponse }
            identifier = id
        }
        if choices.isEmpty { return false }
        guard choices.count == 1, choices[0]["index"] as? Int == 0, !finished,
              let delta = choices[0]["delta"] as? [String: Any], !ChatCompletionsContent.hasCalls(delta["tool_calls"]),
              !ChatCompletionsContent.hasCalls(delta["function_call"]) else { throw AIRequestError.invalidResponse }
        if let role = delta["role"] as? String, role != "assistant" { throw AIRequestError.invalidResponse }
        if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw AIRequestError.refusal }
        if let content = delta["content"], !(content is NSNull), !(content is String) { throw AIRequestError.invalidResponse }
        var progressed = false
        if let content = delta["content"] as? String, !content.isEmpty { text += content; progressed = true }
        if let finish = choices[0]["finish_reason"] as? String {
            guard finish == "stop" else { throw AIRequestError.incomplete }; finished = true; progressed = true
        }
        return progressed
    }
}
