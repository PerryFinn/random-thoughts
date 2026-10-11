import Darwin
import Foundation

// Pipe I/O belongs to one worker; the lock serializes process startup, cancellation and cleanup.
nonisolated final class CodexStdioCheck: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var interruption: CodexSourceError?
    private var buffer = Data()
    private let timeout: TimeInterval

    init(source: CodexSourceIdentity, environment: [String: String], timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = URL(fileURLWithPath: source.executablePath)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = URL(fileURLWithPath: source.dataDirectory, isDirectory: true)
        var environment = environment
        environment["CODEX_HOME"] = source.dataDirectory
        environment["CODEX_SQLITE_HOME"] = source.dataDirectory
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func cancel(_ reason: CodexSourceError) {
        lock.lock()
        defer { lock.unlock() }
        if interruption == nil { interruption = reason }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func run() throws -> CodexVersion? {
        defer { close() }
        do {
            lock.lock()
            defer { lock.unlock() }
            if let interruption { throw interruption }
            // Suppress SIGPIPE on this pipe only; a disappearing child must not terminate the application.
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { throw CodexSourceError.launchFailed }
            try process.run()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        } catch {
            throw (error as? CodexSourceError) ?? .launchFailed
        }
        let deadline = DispatchSource.makeTimerSource()
        deadline.schedule(deadline: .now() + timeout)
        deadline.setEventHandler { [self] in cancel(.timedOut) }
        deadline.resume()
        defer { deadline.cancel() }
        do {
            let initialized = try request("initialize", id: 1, params: [
                "clientInfo": ["name": "random_thoughts", "title": "随想", "version": "1.0.0"],
                "capabilities": ["experimentalApi": false]
            ])
            guard let userAgent = initialized["userAgent"] as? String else { throw CodexSourceError.schemaUnsupported }
            try send(["method": "initialized", "params": [:]])
            var firstID: String?
            for (index, archived) in [false, true].enumerated() {
                let result = try request("thread/list", id: index + 2, params: ["archived": archived, "limit": 1])
                guard let threads = result["data"] as? [[String: Any]], nullableString(result["nextCursor"]) else {
                    throw CodexSourceError.schemaUnsupported
                }
                for thread in threads {
                    let id = try validateThread(thread)
                    if firstID == nil { firstID = id }
                }
            }
            if let firstID {
                let result = try request("thread/read", id: 4, params: ["threadId": firstID, "includeTurns": true])
                guard let thread = result["thread"] as? [String: Any], try validateThread(thread) == firstID else {
                    throw CodexSourceError.schemaUnsupported
                }
            }
            try checkInterruption()
            return CodexVersion.fromUserAgent(userAgent)
        } catch {
            try checkInterruption()
            throw (error as? CodexSourceError) ?? .transportInterrupted
        }
    }

    private func request(_ method: String, id: Int, params: [String: Any]) throws -> [String: Any] {
        try send(["method": method, "id": id, "params": params])
        while true {
            let line = try readLine()
            guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw CodexSourceError.schemaUnsupported
            }
            if response["id"] == nil, response["method"] is String { continue }
            guard response["id"] as? Int == id else { throw CodexSourceError.schemaUnsupported }
            if let error = response["error"] as? [String: Any] {
                switch error["code"] as? Int {
                case -32601: throw CodexSourceError.methodUnsupported
                case -32602: throw CodexSourceError.parametersUnsupported
                default: throw method == "initialize" ? CodexSourceError.handshakeFailed : .readFailed
                }
            }
            guard let result = response["result"] as? [String: Any] else { throw CodexSourceError.schemaUnsupported }
            return result
        }
    }

    private func send(_ message: [String: Any]) throws {
        try checkInterruption()
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readLine() throws -> Data {
        var searchedThrough = buffer.startIndex
        while true {
            try checkInterruption()
            if let newline = buffer[searchedThrough...].firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            guard buffer.count < 64 * 1024 * 1024 else { throw CodexSourceError.readFailed }
            searchedThrough = buffer.endIndex
            var bytes = [UInt8](repeating: 0, count: 16 * 1024)
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw CodexSourceError.transportInterrupted
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    private func checkInterruption() throws {
        lock.lock()
        defer { lock.unlock() }
        if let interruption { throw interruption }
    }

    private func close() {
        try? input.fileHandleForWriting.close()
        lock.lock()
        if process.isRunning {
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
        }
        lock.unlock()
        if process.processIdentifier > 0 { process.waitUntilExit() }
        try? output.fileHandleForReading.close()
        buffer.removeAll()
    }

    private func nullableString(_ value: Any?) -> Bool { value is NSNull || value is String }
    private func timestamp(_ value: Any?, nullable: Bool) -> Bool {
        if nullable, value is NSNull { return true }
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return false }
        return value.doubleValue.isFinite
    }

    private func validateThread(_ thread: [String: Any]) throws -> String {
        guard let id = thread["id"] as? String, !id.isEmpty,
              thread["cwd"] is String, thread["preview"] is String, thread["cliVersion"] is String,
              nullableString(thread["name"]), nullableString(thread["parentThreadId"]),
              thread["source"] is String || thread["source"] is [String: Any],
              nullableString(thread["threadSource"]),
              timestamp(thread["createdAt"], nullable: false), timestamp(thread["updatedAt"], nullable: false),
              timestamp(thread["recencyAt"], nullable: true),
              let turns = thread["turns"] as? [[String: Any]] else { throw CodexSourceError.schemaUnsupported }
        for turn in turns {
            guard turn["id"] is String, turn["status"] is String,
                  timestamp(turn["startedAt"], nullable: true),
                  let items = turn["items"] as? [[String: Any]] else { throw CodexSourceError.schemaUnsupported }
            for item in items {
                guard let type = item["type"] as? String else { throw CodexSourceError.schemaUnsupported }
                switch type {
                case "userMessage":
                    guard item["id"] is String, let content = item["content"] as? [[String: Any]] else { throw CodexSourceError.schemaUnsupported }
                    for input in content {
                        guard let type = input["type"] as? String, type != "text" || input["text"] is String else {
                            throw CodexSourceError.schemaUnsupported
                        }
                    }
                case "agentMessage":
                    guard item["id"] is String, item["text"] is String,
                          item["phase"] == nil || nullableString(item["phase"]) else { throw CodexSourceError.schemaUnsupported }
                default: break
                }
            }
        }
        return id
    }
}
