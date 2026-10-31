import Foundation

nonisolated enum ReportPayload {
    static let keys = ["overview", "completed", "deliverables", "decisions", "risks", "plans"]
    static let schema = #"{"type":"object","properties":{"overview":{"type":"string"},"completed":{"type":"string"},"deliverables":{"type":"string"},"decisions":{"type":"string"},"risks":{"type":"string"},"plans":{"type":"string"}},"required":["overview","completed","deliverables","decisions","risks","plans"],"additionalProperties":false}"#

    static func render(_ payload: String, language: ReportOutputLanguage) throws -> String {
        let sections = try StrictStringObject.parse(payload)
        return try render(sections, language: language)
    }

    @concurrent static func maskAndRender(_ payload: String, language: ReportOutputLanguage, credential: String,
                                         redact: @Sendable (String) throws -> String) async throws -> (markdown: String, redactionFailed: Bool) {
        var sections = try StrictStringObject.parse(payload)
        _ = try render(sections, language: language)
        var failed = false
        for key in keys {
            var body = sections[key]!
            do { body = try redact(body) } catch { failed = true }
            if !credential.isEmpty { body = body.replacingOccurrences(of: credential, with: "[已遮盖凭据]") }
            sections[key] = body
        }
        return (try render(sections, language: language), failed)
    }

    private static func render(_ sections: [String: String], language: ReportOutputLanguage) throws -> String {
        guard Set(sections.keys) == Set(keys) else { throw AIRequestError.invalidResponse }
        let titles = language == .chinese
            ? ["今日概览", "完成事项", "关键产出", "决策与思考", "问题与风险", "明日计划"]
            : ["Today’s Overview", "Completed Work", "Key Deliverables", "Decisions & Rationale", "Issues & Risks", "Tomorrow’s Plan"]
        let markdown = try zip(keys, titles).map { key, title in
            let body = sections[key]!.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let structure = try sectionStructure(in: body)
            guard structure.headers.isEmpty, body.isEmpty || structure.hasContent else { throw AIRequestError.invalidResponse }
            return "## \(title)\n\n" + (body.isEmpty ? language == .chinese ? "无明确内容" : "No confirmed content" : body)
        }.joined(separator: "\n\n")
        guard try sectionStructure(in: markdown).headers.count == titles.count else { throw AIRequestError.invalidResponse }
        return markdown
    }

    private static func sectionStructure(in markdown: String) throws -> (headers: Set<Int>, hasContent: Bool) {
        // Empty headings have no character runs. Give potential ATX headings
        // visible text only in this parsing copy; code/escape context stays intact.
        let visibleHeaders = markdown.replacingOccurrences(of: #"(?m)^([ \t]*(?:>[ \t]*|[-+*][ \t]+|[0-9]{1,9}[.)][ \t]+)*#{1,2})(?=[ \t]|$)"#,
                                                           with: "$1 heading ", options: .regularExpression)
        guard let parsed = try? AttributedString(markdown: visibleHeaders, options: .init(interpretedSyntax: .full)) else {
            throw AIRequestError.invalidResponse
        }
        let headers = Set(parsed.runs.flatMap { run in
            (run.presentationIntent?.components ?? []).compactMap { component in
                if case .header(let level) = component.kind, level <= 2 { return component.identity }
                return nil
            }
        })
        return (headers, !String(parsed.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// JSONSerialization and keyed Decodable silently coalesce duplicate keys. This
// deliberately narrow object grammar accepts only distinct string/string pairs.
nonisolated enum StrictStringObject {
    static func parse(_ value: String) throws -> [String: String] {
        let bytes = Array(value.utf8)
        var index = 0
        func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        func consume(_ byte: UInt8) throws {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { throw AIRequestError.invalidResponse }
            index += 1
        }
        func string() throws -> String {
            whitespace()
            let start = index
            try consume(34)
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if !escaped, byte == 34 {
                    guard let text = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else {
                        throw AIRequestError.invalidResponse
                    }
                    return text
                }
                if !escaped, byte == 92 { escaped = true } else { escaped = false }
            }
            throw AIRequestError.invalidResponse
        }
        try consume(123)
        var object: [String: String] = [:]
        whitespace()
        if index < bytes.count, bytes[index] != 125 {
            while true {
                let key = try string()
                guard object[key] == nil else { throw AIRequestError.invalidResponse }
                try consume(58)
                object[key] = try string()
                whitespace()
                if index < bytes.count, bytes[index] == 125 { break }
                try consume(44)
            }
        }
        try consume(125)
        whitespace()
        guard index == bytes.count else { throw AIRequestError.invalidResponse }
        return object
    }
}
