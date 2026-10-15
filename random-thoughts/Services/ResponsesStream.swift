import Foundation

nonisolated struct ResponsesStream: AIResponseStream {
    private struct Part {
        var text = ""
        var textDone = false
        var done = false
    }
    private struct Item {
        let id: String
        let type: String
        var parts: [Part] = []
        var completed: ResponsesOutput.Item?
    }
    private var framing = ServerSentEvents()
    private var identifier: String?
    private var sequence = -1
    private var progressed = false
    private var items: [Item] = []
    private var result: String?
    var hasTerminated: Bool { result != nil }

    mutating func append(_ data: Data) throws -> Bool {
        var progress = false
        for event in try framing.append(data) { progress = try consume(event) || progress }
        return progress
    }
    mutating func finish() throws -> String {
        for event in try framing.finish() { _ = try consume(event) }
        guard let result else { throw AIRequestError.incomplete }
        return result
    }
    private mutating func consume(_ frame: ServerSentEvents.Event) throws -> Bool {
        guard result == nil, let event = try? JSONDecoder().decode(ResponsesEvent.self, from: Data(frame.data.utf8)),
              frame.name == nil || frame.name == event.type, event.sequenceNumber > sequence else { throw AIRequestError.invalidResponse }
        sequence = event.sequenceNumber
        if event.type == "error" { throw AIHTTPTransport.failure(status: 200, code: event.code, parameter: event.param, service: .responses) }
        if event.type == "response.failed" {
            guard let response = event.response, response.status == "failed",
                  identifier == nil || response.id == identifier else { throw AIRequestError.invalidResponse }
            throw response.error?.reason ?? AIRequestError.unknown
        }
        if event.type == "response.incomplete" { throw AIRequestError.incomplete }
        if event.type.hasPrefix("response.refusal.") { throw AIRequestError.refusal }
        if event.type == "response.created" {
            guard identifier == nil, let response = event.response, response.object == "response", !response.id.isEmpty,
                  response.status == "in_progress", response.output.isEmpty, response.error == nil,
                  response.incompleteDetails == nil else { throw AIRequestError.invalidResponse }
            identifier = response.id
            return true
        }
        guard let identifier else { throw AIRequestError.invalidResponse }
        switch event.type {
        case "response.in_progress":
            guard !progressed, items.isEmpty, let response = event.response, response.id == identifier,
                  response.status == "in_progress", response.output.isEmpty, response.error == nil,
                  response.incompleteDetails == nil else { throw AIRequestError.invalidResponse }
            progressed = true
        case "response.output_item.added":
            guard let index = event.outputIndex, index == items.count, let item = event.item, !item.id.isEmpty,
                  !items.contains(where: { $0.id == item.id }), ["message", "reasoning"].contains(item.type),
                  item.status == "in_progress" || (item.type == "reasoning" && item.status == nil),
                  item.type != "message" || (item.role == "assistant" && item.content?.isEmpty == true) else { throw AIRequestError.invalidResponse }
            items.append(Item(id: item.id, type: item.type))
        case "response.content_part.added":
            let index = try itemIndex(event)
            guard let content = event.contentIndex, content == items[index].parts.count, let part = event.part else { throw AIRequestError.invalidResponse }
            if part.type == "refusal" { throw AIRequestError.refusal }
            guard part.type == "output_text", part.text == "", items[index].type == "message" else { throw AIRequestError.invalidResponse }
            items[index].parts.append(Part())
        case "response.output_text.delta", "response.output_text.done", "response.content_part.done":
            let index = try itemIndex(event)
            guard let content = event.contentIndex, items[index].parts.indices.contains(content),
                  !items[index].parts[content].done else { throw AIRequestError.invalidResponse }
            switch event.type {
            case "response.output_text.delta":
                guard !items[index].parts[content].textDone, let delta = event.delta else { throw AIRequestError.invalidResponse }
                items[index].parts[content].text += delta
                return !delta.isEmpty
            case "response.output_text.done":
                guard !items[index].parts[content].textDone, let text = event.text,
                      text.utf8.elementsEqual(items[index].parts[content].text.utf8) else { throw AIRequestError.invalidResponse }
                items[index].parts[content].textDone = true
            default:
                guard items[index].parts[content].textDone, let part = event.part, part.type == "output_text",
                      part.text?.utf8.elementsEqual(items[index].parts[content].text.utf8) == true else { throw AIRequestError.invalidResponse }
                items[index].parts[content].done = true
            }
        case "response.output_item.done":
            guard let index = event.outputIndex, items.indices.contains(index), let item = event.item,
                  item.id == items[index].id, item.type == items[index].type, items[index].completed == nil else { throw AIRequestError.invalidResponse }
            if item.type == "message" {
                guard item.role == "assistant", item.status == "completed", let content = item.content,
                      !content.isEmpty, content.count == items[index].parts.count, items[index].parts.allSatisfy(\.done),
                      zip(content, items[index].parts).allSatisfy({ $0.type == "output_text" && $0.text?.utf8.elementsEqual($1.text.utf8) == true }) else {
                    throw AIRequestError.invalidResponse
                }
            } else if item.status != nil && item.status != "completed" { throw AIRequestError.incomplete }
            items[index].completed = item
        case "response.completed":
            guard let response = event.response, response.id == identifier, response.output.count == items.count,
                  zip(response.output, items).allSatisfy({ output, state in
                      guard let done = state.completed, output.id == done.id, output.type == done.type else { return false }
                      if output.type == "reasoning" { return true }
                      guard output.role == done.role, output.status == done.status, let content = output.content,
                            let completed = done.content, content.count == completed.count else { return false }
                      return zip(content, completed).allSatisfy { $0.type == $1.type && $0.text?.utf8.elementsEqual(($1.text ?? "").utf8) == true }
                  }) else { throw AIRequestError.invalidResponse }
            result = try response.completedText()
        default: return false
        }
        return true
    }
    private func itemIndex(_ event: ResponsesEvent) throws -> Int {
        guard let index = event.outputIndex, items.indices.contains(index), items[index].id == event.itemID,
              items[index].completed == nil else { throw AIRequestError.invalidResponse }
        return index
    }
}

private nonisolated struct ResponsesEvent: Decodable {
    let type: String
    let sequenceNumber: Int
    let response: ResponsesOutput?
    let item: ResponsesOutput.Item?
    let part: ResponsesOutput.Item.Content?
    let outputIndex: Int?
    let contentIndex: Int?
    let itemID: String?
    let delta: String?
    let text: String?
    let code: String?
    let param: String?
    enum CodingKeys: String, CodingKey {
        case type, response, item, part, delta, text, code, param
        case sequenceNumber = "sequence_number", outputIndex = "output_index", contentIndex = "content_index", itemID = "item_id"
    }
}
