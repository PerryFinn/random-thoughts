import Darwin
import Foundation

@main
struct SyntheticCodexServer {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard CommandLine.arguments.dropFirst() == ["app-server"],
              let root = environment["RANDOM_THOUGHTS_TEST_ROOT"],
              let home = environment["CODEX_HOME"], home.hasPrefix(root + "/"),
              environment["CODEX_SQLITE_HOME"] == home,
              FileManager.default.currentDirectoryPath == home else { exit(2) }
        let directory = URL(fileURLWithPath: home)
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("fixture.json"))) as? [String: String]
        let scenario = fixture?["scenario"] ?? "success"
        try Data(String(getpid()).utf8).write(to: directory.appendingPathComponent("pid"))
        try FileHandle.standardError.write(contentsOf: Data(String(repeating: "STDERR_SECRET_25", count: 10_000).utf8))
        if scenario == "blocked" {
            let signal = try FileHandle(forWritingTo: directory.appendingPathComponent("ready"))
            try signal.write(contentsOf: Data([1]))
            try signal.close()
        }
        var initialized = false
        var acknowledged = false
        while let line = readLine() {
            guard let data = line.data(using: .utf8), let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String else { exit(3) }
            let id = request["id"] as? Int
            let params = request["params"] as? [String: Any] ?? [:]
            if scenario == "blocked" || scenario == "timeout" { while true { pause() } }
            if method == "initialize" {
                guard !initialized, id != nil,
                      let client = params["clientInfo"] as? [String: Any], client["name"] as? String == "random_thoughts",
                      (params["capabilities"] as? [String: Any])?["experimentalApi"] as? Bool == false else { exit(4) }
                initialized = true
                if scenario == "handshake" {
                    try emit(["id": id!, "error": ["code": -32000, "message": "ERROR_SECRET_25"]])
                } else {
                    let version = scenario == "old-version" ? "0.1.0" : scenario == "no-version" ? "UNPARSED_SECRET_25" : "9.8.7"
                    try emit(["id": id!, "result": ["userAgent": "random_thoughts/\(version) (STDOUT_SECRET_25)"]])
                }
            } else if method == "initialized" {
                guard initialized, !acknowledged, id == nil else { exit(5) }
                acknowledged = true
            } else {
                guard acknowledged, let id else { exit(6) }
                try emit(["method": "synthetic/notice", "params": ["marker": "NOTIFICATION_SECRET_25"]])
                if method == "thread/list" {
                    guard params["archived"] is Bool, params["limit"] as? Int == 1 else { exit(7) }
                    if scenario == "method" || scenario == "parameters" {
                        try emit(["id": id, "error": ["code": scenario == "method" ? -32601 : -32602, "message": "ERROR_SECRET_25"]])
                        continue
                    }
                    if scenario == "transport" { return }
                    if scenario == "malformed" {
                        try FileHandle.standardOutput.write(contentsOf: Data("RAW_SECRET_25\n".utf8))
                        continue
                    }
                    var listed = thread(scenario: scenario, includeTurns: false)
                    if scenario == "schema-list" { listed.removeValue(forKey: "createdAt") }
                    let empty = scenario == "empty" || (scenario == "archived" && params["archived"] as? Bool == false)
                    let threads: [[String: Any]] = empty ? [] : [listed]
                    try emit(["id": id, "result": ["data": threads, "nextCursor": NSNull()]])
                } else if method == "thread/read" {
                    guard params["includeTurns"] as? Bool == true, params["threadId"] as? String == "SESSION_SECRET_25" else { exit(8) }
                    if scenario == "read" {
                        try emit(["id": id, "error": ["code": -32000, "message": "ERROR_SECRET_25"]])
                    } else {
                        try emit(["id": id, "result": ["thread": thread(scenario: scenario, includeTurns: true)]])
                    }
                } else { exit(9) }
            }
        }
    }

    private static func thread(scenario: String, includeTurns: Bool) -> [String: Any] {
        let userText: Any = scenario == "schema-read" ? 42 : "BODY_SECRET_25"
        let assistantText = scenario == "large" && includeTurns ? String(repeating: "L", count: 9 * 1024 * 1024) : "FINAL_SECRET_25"
        var items: [[String: Any]] = [
            ["id": "USER_SECRET_25", "type": "userMessage", "content": [["type": "text", "text": userText]]],
            ["id": "AGENT_SECRET_25", "type": "agentMessage", "text": assistantText, "phase": "final_answer"]
        ]
        if scenario == "unknown" { items.append(["type": "futureContent", "secret": "UNKNOWN_SECRET_25"]) }
        let turns: [[String: Any]] = includeTurns ? [["id": "TURN_SECRET_25", "startedAt": 1000, "completedAt": 2000,
                                                     "status": "completed", "items": items]] : []
        return ["id": "SESSION_SECRET_25", "preview": "TITLE_SECRET_25", "name": NSNull(),
         "cwd": "/synthetic/WORK_DIRECTORY_SECRET_25", "source": "cli", "parentThreadId": NSNull(), "threadSource": NSNull(),
         "createdAt": 1000, "updatedAt": 2000, "recencyAt": 1000, "cliVersion": "9.8.7", "status": ["type": "notLoaded"],
         "turns": turns]
    }

    private static func emit(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
