import Darwin
import Foundation
import Testing
@testable import random_thoughts

@MainActor
@Suite(.serialized)
struct CodexSessionWireTests {
    @Test func explicitUserClassificationsKeepInteractiveSourcesSelectedWithoutTrustingUnknownSources() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let sources: [Any] = ["cli", "vscode", "appServer", "unknown", "exec", ["custom": "synthetic"]]
        var threads: [[String: Any]] = []
        for (index, source) in sources.enumerated() {
            var thread = syntheticSession(id: "source-\(index)", name: nil, cwd: "", source: source,
                turns: [syntheticTurn(id: "turn-\(index)", at: 1000, user: "合成用户")])
            thread["threadSource"] = "user"
            threads.append(thread)
        }
        var unrecognized = threads[0]
        unrecognized["id"] = "unrecognized"
        unrecognized["threadSource"] = "future-classification"
        threads.append(unrecognized)
        let fixture: [String: Any] = ["scenario": "scan", "currentPages": [threads], "archivedPages": [[]],
            "threads": Dictionary(uniqueKeysWithValues: threads.map { ($0["id"] as! String, $0) })]
        let reader = try scanReader(environment, fixture: fixture)
        let result = try await reader.scan(scanIdentity(environment), day: ReportDay(date: environment.clock.now, timeZone: .gmt), progress: { _ in })
        #expect(result.sessions.prefix(3).map(\.origin) == [.user, .user, .user])
        #expect(result.sessions.dropFirst(3).allSatisfy { $0.origin == .unknown })
        try expectScanChildReaped(environment)
    }

    @Test func cancellingARealScanReapsItsChildAndDoesNotRestartIt() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "fault": "blocked"])
        let path = environment.directory.appendingPathComponent("scan-ready").path
        #expect(mkfifo(path, 0o600) == 0)
        let ready = Task.detached {
            let descriptor = Darwin.open(path, O_RDONLY)
            guard descriptor >= 0 else { throw CodexSourceError.transportInterrupted }
            defer { Darwin.close(descriptor) }
            var byte: UInt8 = 0
            guard Darwin.read(descriptor, &byte, 1) == 1 else { throw CodexSourceError.transportInterrupted }
        }
        let identity = try scanIdentity(environment)
        let day = ReportDay(date: environment.clock.now, timeZone: .gmt)
        let task = Task { try await reader.scan(identity, day: day, progress: { _ in }) }
        try await ready.value
        task.cancel()
        await #expect(throws: CodexSourceError.cancelled) { try await task.value }
        #expect(try String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8) == "1")
        try expectScanChildReaped(environment)
    }

    @Test func mixedWireKeepsOnlyOrderedTextAndFinalAnswersAndNeverReadsInternalSources() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var turn = syntheticTurn(id: "mixed", at: 1000, user: "")
        turn["items"] = [
            ["id": "user", "type": "userMessage", "content": [
                ["type": "text", "text": "第一段 /normal/path", "text_elements": [["text": "METADATA_EXCLUDED_26"]]],
                ["type": "image", "url": "IMAGE_EXCLUDED_26"], ["type": "skill", "name": "SKILL_EXCLUDED_26"],
                ["type": "mention", "path": "MENTION_EXCLUDED_26"], ["type": "future", "text": "UNKNOWN_EXCLUDED_26"],
                ["type": "text", "text": "第二段", "text_elements": []]
            ]],
            ["id": "comment", "type": "agentMessage", "phase": "commentary", "text": "COMMENTARY_EXCLUDED_26"],
            ["id": "missing", "type": "agentMessage", "text": "MISSING_PHASE_EXCLUDED_26"],
            ["id": "future", "type": "agentMessage", "phase": "future", "text": "FUTURE_PHASE_EXCLUDED_26"],
            ["id": "final", "type": "agentMessage", "phase": "final_answer", "text": "唯一最终回复"],
            ["type": "commandExecution", "output": "COMMAND_EXCLUDED_26"],
            ["type": "reasoning", "text": "REASONING_EXCLUDED_26"]
        ] as [[String: Any]]
        let allowed = syntheticSession(id: "allowed", name: nil, cwd: "", turns: [turn,
            syntheticTurn(id: "empty-user", at: 1001, user: " \n", final: "助手不能单独证明用户活动")])
        var internalSessions: [[String: Any]] = []
        for (index, classification) in ["automation", "subagent", "memory_consolidation"].enumerated() {
            var item = syntheticSession(id: "internal-\(index)", name: nil, cwd: "", turns: [])
            item["threadSource"] = classification
            internalSessions.append(item)
        }
        var child = syntheticSession(id: "parent-linked", name: nil, cwd: "", turns: [])
        child["parentThreadId"] = "synthetic-parent"
        internalSessions.append(child)
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "currentPages": [[allowed] + internalSessions],
            "archivedPages": [[]], "threads": ["allowed": allowed]])
        let result = try await reader.scan(scanIdentity(environment), day: ReportDay(date: environment.clock.now, timeZone: .gmt), progress: { _ in })
        #expect(result.sessions.map(\.id) == ["allowed"])
        #expect(result.sessions[0].turns.count == 1)
        #expect(result.sessions[0].turns[0].userText == "第一段 /normal/path第二段")
        #expect(result.sessions[0].turns[0].finalAnswer == "唯一最终回复")
        try expectScanChildReaped(environment)
    }

    @Test func completeEmptyScanIsAvailableAndTheFallDSTDayIncludesBothRepeatedHours() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let day = try ReportDay(calendarDate: "2026-11-01", timeZoneIdentifier: "America/Los_Angeles")
        #expect(day.interval.duration == 25 * 3600)
        let empty = try scanReader(environment, fixture: ["scenario": "scan", "currentPages": [[]], "archivedPages": [[]]])
        let emptyScan = try await empty.scan(scanIdentity(environment), day: day, progress: { _ in })
        #expect(emptyScan.sessions.isEmpty && !emptyScan.isPartial)
        let thread = syntheticSession(id: "fall", name: "", cwd: "", turns: [
            syntheticTurn(id: "first-hour", at: day.start.timeIntervalSince1970 + 5400, user: "首次 01:30"),
            syntheticTurn(id: "second-hour", at: day.start.timeIntervalSince1970 + 9000, user: "再次 01:30")
        ])
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "currentPages": [[thread]], "archivedPages": [[]], "threads": ["fall": thread]])
        let scan = try await reader.scan(scanIdentity(environment), day: day, progress: { _ in })
        #expect(scan.sessions[0].turns.map(\.id) == ["first-hour", "second-hour"])
        #expect(scan.sessions[0].title == "预览 fall")
        try expectScanChildReaped(environment)
    }

    @Test(arguments: ["method", "parameters", "schema", "cursor-loop", "list-failure", "all-unread", "summary", "transport-always", "timeout-always"])
    func incompleteRangesAndUnsupportedContractsCannotBecomeSnapshotsOrRetryIndefinitely(_ fault: String) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var thread = syntheticSession(id: "candidate", name: nil, cwd: "", turns: [syntheticTurn(id: "turn", at: 1000, user: "候选")])
        if fault == "summary" {
            var turns = thread["turns"] as! [[String: Any]]
            turns[0]["itemsView"] = "summary"
            thread["turns"] = turns
        }
        let fixture: [String: Any] = ["scenario": "scan", "fault": fault, "currentPages": [[thread]], "archivedPages": [[]],
                                     "threads": ["candidate": thread], "readFailures": fault == "all-unread" ? ["candidate"] : []]
        let reader = try scanReader(environment, fixture: fixture, timeout: fault == "timeout-always" ? 0.05 : 5)
        let expected: CodexSourceError
        switch fault {
        case "method": expected = .methodUnsupported
        case "parameters": expected = .parametersUnsupported
        case "schema", "cursor-loop", "summary": expected = .schemaUnsupported
        case "transport-always": expected = .transportInterrupted
        case "timeout-always": expected = .timedOut
        default: expected = .readFailed
        }
        await #expect(throws: expected) {
            try await reader.scan(scanIdentity(environment), day: ReportDay(date: environment.clock.now, timeZone: .gmt), progress: { _ in })
        }
        #expect(try String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8)
                == (["transport-always", "timeout-always"].contains(fault) ? "2" : "1"))
        try expectScanChildReaped(environment)
    }

    @Test func aCompleteRangeAllowsOnlyReadableCandidatesToBeConfirmedAsAPartialScan() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let good = syntheticSession(id: "good", name: nil, cwd: "", turns: [syntheticTurn(id: "turn", at: 1000, user: "可读")])
        let bad = syntheticSession(id: "bad", name: "不可读会话", cwd: "", turns: [])
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "currentPages": [[good, bad]],
            "archivedPages": [[]], "threads": ["good": good, "bad": bad], "readFailures": ["bad"]])
        let result = try await reader.scan(scanIdentity(environment), day: ReportDay(date: environment.clock.now, timeZone: .gmt), progress: { _ in })
        #expect(result.isPartial)
        #expect(result.sessions.map(\.id) == ["good"])
        #expect(result.failures.map(\.id) == ["bad"])
        #expect(try String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8) == "1")
        try expectScanChildReaped(environment)
    }

    @Test func anInterruptedScanRestartsOnceAndReturnsOnlyTheCompleteSecondAttempt() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let day = ReportDay(date: environment.clock.now, timeZone: TimeZone(identifier: "Etc/UTC")!)
        let thread = syntheticSession(id: "retry", name: nil, cwd: "", turns: [syntheticTurn(id: "turn", at: 1000, user: "重启后的完整输入")])
        let reader = try scanReader(environment, fixture: ["scenario": "scan", "fault": "transport-once",
            "currentPages": [[thread]], "archivedPages": [[]], "threads": ["retry": thread]])
        let result = try await reader.scan(scanIdentity(environment), day: day, progress: { _ in })
        #expect(result.sessions.map(\.id) == ["retry"])
        #expect(try String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8) == "2")
        try expectScanChildReaped(environment)
    }

    @Test func realWirePagesBothListsPrefersCurrentAndFiltersTurnsAtTheDSTBoundary() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let day = try ReportDay(calendarDate: "2026-03-08", timeZoneIdentifier: "America/Los_Angeles")
        let first = syntheticSession(id: "current", name: "当前标题", cwd: "/synthetic/project/./main", turns: [
            syntheticTurn(id: "background", at: day.start.timeIntervalSince1970 - 1, user: "背景"),
            syntheticTurn(id: "midnight", at: day.start.timeIntervalSince1970, user: "当天用户", final: "跨午夜结果"),
            syntheticTurn(id: "undated", at: nil, user: "日期不明"),
            syntheticTurn(id: "future", at: day.interval.end.timeIntervalSince1970, user: "未来")
        ])
        let other = syntheticSession(id: "worktree", name: nil, cwd: "/synthetic/project/worktrees/second",
                                     turns: [syntheticTurn(id: "last", at: day.interval.end.timeIntervalSince1970 - 1, user: "最后一秒")])
        var archivedDuplicate = first
        archivedDuplicate["name"] = "归档重复标题"
        let unknown = syntheticSession(id: "unknown", name: nil, cwd: "", source: "unknown",
                                       turns: [syntheticTurn(id: "unknown-turn", at: day.start.timeIntervalSince1970, user: "未知用户")])
        let internalSession = syntheticSession(id: "internal", name: "内部", cwd: "/synthetic/project", source: ["subAgent": "memory_consolidation"], turns: [])
        let fixture: [String: Any] = ["scenario": "scan", "currentPages": [[first], [other, internalSession]],
                                     "archivedPages": [[archivedDuplicate], [unknown]],
                                     "threads": ["current": first, "worktree": other, "unknown": unknown]]
        let reader = try scanReader(environment, fixture: fixture)
        let result = try await reader.scan(scanIdentity(environment), day: day, progress: { _ in })
        #expect(!result.isPartial)
        #expect(result.sessions.map(\.id) == ["current", "worktree", "unknown"])
        #expect(result.sessions[0].title == "当前标题")
        #expect(result.sessions[0].workDirectory == "/synthetic/project/main")
        #expect(result.sessions[0].turns.map(\.id) == ["midnight"])
        #expect(result.sessions[0].background.map(\.userText) == ["背景"])
        #expect(result.sessions[0].turns[0].finalAnswer == "跨午夜结果")
        #expect(result.sessions[1].turns[0].isResultConfirmed == false)
        #expect(result.sessions[2].origin == .unknown)
        #expect(result.sessions[2].workDirectory == nil)
        #expect(day.interval.duration == 23 * 3600)
        try expectScanChildReaped(environment)
    }
}

@MainActor
func scanReader(_ environment: IsolatedTestEnvironment, fixture: [String: Any], timeout: TimeInterval = 30) throws -> CodexDataSourceReader {
    try JSONSerialization.data(withJSONObject: fixture).write(to: environment.directory.appendingPathComponent("fixture.json"))
    return CodexDataSourceReader(homeDirectory: environment.directory,
                                 environment: ["RANDOM_THOUGHTS_TEST_ROOT": try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_TEST_ROOT"])],
                                 homebrewDirectories: [], timeout: timeout, scanLockDirectory: environment.directory.appendingPathComponent("locks"))
}

@MainActor
func scanIdentity(_ environment: IsolatedTestEnvironment) throws -> CodexSourceIdentity {
    CodexSourceIdentity(executablePath: try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"]),
                        dataDirectory: environment.directory.path)
}

@MainActor
func expectScanChildReaped(_ environment: IsolatedTestEnvironment) throws {
    let pid = try #require(Int32(String(decoding: Data(contentsOf: environment.directory.appendingPathComponent("pid")), as: UTF8.self)))
    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}

func syntheticSession(id: String, name: String?, cwd: String, source: Any = "cli", turns: [[String: Any]]) -> [String: Any] {
    ["id": id, "sessionId": id, "forkedFromId": NSNull(), "parentThreadId": NSNull(), "preview": "预览 \(id)",
     "ephemeral": false, "section": NSNull(), "sectionEnteredAt": NSNull(), "modelProvider": "synthetic",
     "createdAt": 1, "updatedAt": 2, "recencyAt": NSNull(), "status": ["type": "notLoaded"], "path": NSNull(),
     "cwd": cwd, "cliVersion": "9.8.7", "source": source, "threadSource": NSNull(), "agentNickname": NSNull(),
     "agentRole": NSNull(), "gitInfo": NSNull(), "name": name as Any? ?? NSNull(), "turns": turns]
}

func syntheticTurn(id: String, at: Double?, user: String, final: String? = nil) -> [String: Any] {
    var items: [[String: Any]] = [["id": "user-\(id)", "type": "userMessage", "content": [["type": "text", "text": user, "text_elements": []]]]]
    if let final { items.append(["id": "agent-\(id)", "type": "agentMessage", "text": final, "phase": "final_answer"]) }
    return ["id": id, "startedAt": at as Any? ?? NSNull(), "completedAt": NSNull(), "durationMs": NSNull(),
            "status": "completed", "error": NSNull(), "itemsView": "full", "items": items]
}
