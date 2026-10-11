import Foundation

nonisolated enum CodexSessionContent {
    struct Metadata {
        let id: String
        let title: String
        let workDirectory: String?
        let origin: CodexSessionOrigin?
    }

    static func metadata(_ thread: [String: Any]) -> Metadata {
        let name = (thread["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = (thread["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cwd = thread["cwd"] as? String ?? ""
        let source = thread["source"]
        let classification = thread["threadSource"] as? String
        let object = source as? [String: Any]
        let origin: CodexSessionOrigin?
        if thread["parentThreadId"] is String || object?["subAgent"] != nil || object?["internal"] != nil
            || ["automation", "subagent", "memory_consolidation"].contains(classification ?? "") {
            origin = nil
        } else if ["cli", "vscode", "appServer"].contains(source as? String ?? ""), classification == nil || classification == "user" {
            origin = .user
        } else {
            origin = .unknown
        }
        return Metadata(id: thread["id"] as! String, title: !name.isEmpty ? name : !preview.isEmpty ? preview : "未命名会话",
                        workDirectory: cwd.isEmpty ? nil : URL(fileURLWithPath: cwd).standardizedFileURL.path, origin: origin)
    }

    static func candidate(_ thread: [String: Any], listed: Metadata, day: ReportDay) throws -> CodexCandidateSession? {
        let read = metadata(thread)
        guard let listedOrigin = listed.origin, let readOrigin = read.origin else { return nil }
        var compliant: [(Int, CodexWorkTurn)] = []
        for (index, turn) in (thread["turns"] as! [[String: Any]]).enumerated() {
            guard turn["itemsView"] as? String == "full" else { throw CodexSourceError.schemaUnsupported }
            guard let startedAt = turn["startedAt"] as? NSNumber else { continue }
            let seconds = startedAt.doubleValue
            guard (-62135596800...253402300799).contains(seconds) else { throw CodexSourceError.schemaUnsupported }
            let start = Date(timeIntervalSince1970: seconds)
            guard start < day.interval.end else { continue }
            let items = turn["items"] as! [[String: Any]]
            let user = items.filter { $0["type"] as? String == "userMessage" }.map { item in
                (item["content"] as! [[String: Any]]).filter { $0["type"] as? String == "text" }
                    .map { $0["text"] as! String }.joined()
            }.joined(separator: "\n")
            guard !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let final = items.filter { $0["type"] as? String == "agentMessage" && $0["phase"] as? String == "final_answer" }
                .map { $0["text"] as! String }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            compliant.append((index, CodexWorkTurn(id: turn["id"] as! String, startedAt: start,
                                                  day: ReportDay(date: start, timeZone: day.timeZone),
                                                  userText: user, finalAnswer: final.isEmpty ? nil : final)))
        }
        compliant.sort { ($0.1.startedAt, $0.0) < ($1.1.startedAt, $1.0) }
        let today = compliant.map(\.1).filter { $0.startedAt >= day.start }
        guard let first = today.first else { return nil }
        return CodexCandidateSession(id: listed.id, title: listed.title, workDirectory: listed.workDirectory,
                                     origin: listedOrigin == .user && readOrigin == .user ? .user : .unknown,
                                     turns: today, background: compliant.map(\.1).filter { $0.startedAt < first.startedAt })
    }
}
