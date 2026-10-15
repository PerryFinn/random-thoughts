import Foundation

nonisolated struct MessagesStream: AIResponseStream {
    private struct Block { let index: Int; let type: String; var hasSignature: Bool }
    private var framing = ServerSentEvents()
    private var started = false
    private var blocks = 0
    private var active: Block?
    private var ending = false
    private var completed = false
    private var text = ""
    private var result: String?
    var hasTerminated: Bool { result != nil }

    mutating func append(_ data: Data) throws -> Bool {
        var progress = false
        for frame in try framing.append(data) { progress = try consume(frame) || progress }
        return progress
    }
    mutating func finish() throws -> String {
        for frame in try framing.finish() { _ = try consume(frame) }
        guard let result else { throw AIRequestError.incomplete }
        return result
    }
    private mutating func consume(_ frame: ServerSentEvents.Event) throws -> Bool {
        guard result == nil, let event = try? JSONDecoder().decode(MessagesEvent.self, from: Data(frame.data.utf8)),
              frame.name == nil || frame.name == event.type else { throw AIRequestError.invalidResponse }
        switch event.type {
        case "error":
            throw AIHTTPTransport.failure(status: 200, data: Data(frame.data.utf8), service: .messages)
        case "ping": return false
        case "message_start":
            guard !started, let message = event.message, message.type == "message", message.role == "assistant", !message.id.isEmpty,
                  message.content.isEmpty, message.stopReason == nil, message.stopSequence == nil, message.stopDetails == nil else {
                throw AIRequestError.invalidResponse
            }
            started = true
        case "content_block_start":
            guard started, !ending, active == nil, event.index == blocks, let content = event.contentBlock,
                  ["text", "thinking", "redacted_thinking"].contains(content.type) else { throw AIRequestError.invalidResponse }
            if content.type == "text" {
                guard let value = content.text else { throw AIRequestError.invalidResponse }
                text += value
            }
            active = Block(index: blocks, type: content.type, hasSignature: content.signature?.isEmpty == false)
            blocks += 1
        case "content_block_delta":
            guard var block = active, event.index == block.index, let delta = event.delta else { throw AIRequestError.invalidResponse }
            switch (block.type, delta.type) {
            case ("text", "text_delta"):
                guard let value = delta.text else { throw AIRequestError.invalidResponse }
                text += value
                return !value.isEmpty
            case ("thinking", "thinking_delta"):
                guard !block.hasSignature, let value = delta.thinking else { throw AIRequestError.invalidResponse }
                return !value.isEmpty
            case ("thinking", "signature_delta"):
                guard let value = delta.signature else { throw AIRequestError.invalidResponse }
                block.hasSignature = block.hasSignature || !value.isEmpty
                active = block
                return !value.isEmpty
            default: throw AIRequestError.invalidResponse
            }
        case "content_block_stop":
            guard let block = active, event.index == block.index,
                  block.type != "thinking" || block.hasSignature else { throw AIRequestError.invalidResponse }
            active = nil
        case "message_delta":
            guard started, active == nil, blocks > 0, let delta = event.delta else { throw AIRequestError.invalidResponse }
            ending = true
            if delta.stopReason != nil {
                guard !completed else { throw AIRequestError.invalidResponse }
                try MessagesOutput.requireCompletion(reason: delta.stopReason, sequence: delta.stopSequence, details: delta.stopDetails)
                completed = true
                return true
            }
            guard delta.stopSequence == nil, delta.stopDetails == nil else { throw AIRequestError.invalidResponse }
            return false
        case "message_stop":
            guard completed, active == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIRequestError.incomplete
            }
            result = text
        default: return false
        }
        return true
    }
}

private nonisolated struct MessagesEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let thinking: String?
        let signature: String?
        let stopReason: String?
        let stopSequence: String?
        let stopDetails: MessagesOutput.StopDetails?
        enum CodingKeys: String, CodingKey {
            case type, text, thinking, signature
            case stopReason = "stop_reason", stopSequence = "stop_sequence", stopDetails = "stop_details"
        }
    }
    let type: String
    let message: MessagesOutput?
    let index: Int?
    let contentBlock: MessagesOutput.Content?
    let delta: Delta?
    enum CodingKeys: String, CodingKey { case type, message, index, delta; case contentBlock = "content_block" }
}
