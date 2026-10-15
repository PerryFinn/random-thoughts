import Foundation

nonisolated protocol AIResponseStream: Sendable {
    var hasTerminated: Bool { get }
    mutating func append(_ data: Data) throws -> Bool
    mutating func finish() throws -> String
}

// Framing only: each protocol interprets its own event payloads and termination.
nonisolated struct ServerSentEvents {
    struct Event { let name: String?; let data: String }
    private var buffer = Data()
    private var name: String?
    private var lines: [String] = []

    mutating func append(_ data: Data) throws -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        while let end = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let next = buffer.index(after: end)
            if buffer[end] == 13, next == buffer.endIndex { break }
            let after = buffer[end] == 13 && buffer[next] == 10 ? buffer.index(after: next) : next
            guard let line = String(data: buffer[..<end], encoding: .utf8) else { throw AIRequestError.invalidResponse }
            buffer.removeSubrange(..<after)
            if let event = consume(line) { events.append(event) }
        }
        return events
    }
    mutating func finish() throws -> [Event] {
        var events: [Event] = []
        if buffer == Data([13]) {
            if let event = consume("") { events.append(event) }
            buffer.removeAll()
        }
        guard buffer.allSatisfy({ [9, 10, 13, 32].contains($0) }), lines.isEmpty, name == nil else { throw AIRequestError.incomplete }
        return events
    }
    private mutating func consume(_ line: String) -> Event? {
        if line.isEmpty {
            defer { lines.removeAll(keepingCapacity: true); name = nil }
            return lines.isEmpty ? nil : Event(name: name, data: lines.joined(separator: "\n"))
        }
        guard !line.hasPrefix(":") else { return nil }
        let separator = line.firstIndex(of: ":") ?? line.endIndex
        let field = line[..<separator]
        var value = separator == line.endIndex ? "" : String(line[line.index(after: separator)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        if field == "data" { lines.append(value) }
        if field == "event" { name = value.isEmpty ? nil : value }
        return nil
    }
}
