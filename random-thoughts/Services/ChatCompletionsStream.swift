import Foundation

nonisolated struct ChatCompletionsStream {
    private var buffer = Data()
    private var text = ""
    private var finished = false
    private var done = false
    private var identifier: String?
    private var lines: [String] = []
    var hasTerminated: Bool { done }

    mutating func append(_ data: Data) throws -> Bool {
        buffer.append(data)
        var progressed = false
        while let end = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let next = buffer.index(after: end)
            if buffer[end] == 13, next == buffer.endIndex { break }
            let after = buffer[end] == 13 && buffer[next] == 10 ? buffer.index(after: next) : next
            guard let line = String(data: buffer[..<end], encoding: .utf8) else { throw AIRequestError.invalidResponse }
            buffer.removeSubrange(..<after)
            if line.isEmpty {
                progressed = try consume(lines.joined(separator: "\n")) || progressed
                lines.removeAll(keepingCapacity: true)
            } else { lines.append(line) }
        }
        return progressed
    }
    mutating func finish() throws -> String {
        if buffer == Data([13]) {
            _ = try consume(lines.joined(separator: "\n")); lines.removeAll(); buffer.removeAll()
        }
        guard buffer.allSatisfy({ [9, 10, 13, 32].contains($0) }), lines.isEmpty, done, finished,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.incomplete }
        return text
    }
    private mutating func consume(_ event: String) throws -> Bool {
        let payload = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }.map {
            var line = String($0.dropFirst(5)); if line.hasPrefix(" ") { line.removeFirst() }
            if line.hasSuffix("\r") { line.removeLast() }; return line
        }.joined(separator: "\n")
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
