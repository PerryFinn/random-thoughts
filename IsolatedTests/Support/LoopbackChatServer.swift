import Darwin
import Foundation
import Synchronization

// Only the exact loopback port selected by test-isolated.sh is permitted.
// This exercises URLSession's real HTTP/redirect/SSE mechanisms with synthetic data.
final class LoopbackChatServer: @unchecked Sendable {
    struct State {
        var connection: Int32 = -1
        var request: Data?
        var observer: CheckedContinuation<Data, any Error>?
        var closed = false
    }
    private let state = Mutex(State())
    private let listener: Int32
    let endpoint: URL

    init() throws {
        guard let raw = ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CHAT_PORT"],
              let port = UInt16(raw), port > 0 else { throw Failure.setup }
        endpoint = URL(string: "http://127.0.0.1:\(port)/complete?synthetic=28")!
        listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw Failure.setup }
        var reuse: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { Darwin.close(listener); throw Failure.setup }
        DispatchQueue.global(qos: .userInitiated).async { self.receiveRequest() }
    }

    func request() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { value in
                if let request = value.request { continuation.resume(returning: request) }
                else if value.closed { continuation.resume(throwing: Failure.closed) }
                else { value.observer = continuation }
            }
        }
    }

    func headers(status: Int = 200, fields: [String: String] = [:], length: Int? = nil) throws {
        var values = fields
        values["Connection"] = "close"
        if let length { values["Content-Length"] = "\(length)" }
        else { values["Content-Type"] = "text/event-stream" }
        let text = "HTTP/1.1 \(status) Synthetic\r\n" + values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        try write(Data(text.utf8))
    }
    func respond(_ body: Data, status: Int = 200, fields: [String: String] = [:]) throws {
        try headers(status: status, fields: fields, length: body.count)
        try write(body)
        finish()
    }
    func write(_ data: Data) throws {
        let descriptor = state.withLock { $0.connection }
        guard descriptor >= 0 else { throw Failure.closed }
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { throw Failure.closed }
                sent += count
            }
        }
    }
    func finish() {
        let descriptor = state.withLock { value in let old = value.connection; value.connection = -1; return old }
        if descriptor >= 0 { shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor) }
    }
    func close() {
        let first = state.withLock { value in
            if value.closed { return false }
            value.closed = true; value.observer?.resume(throwing: Failure.closed); value.observer = nil
            return true
        }
        if first { shutdown(listener, SHUT_RDWR); Darwin.close(listener); finish() }
    }
    private func receiveRequest() {
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { close(); return }
        var noSignal: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let active = state.withLock { value in
            if value.closed { return false }; value.connection = connection; return true
        }
        guard active else { Darwin.close(connection); return }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(connection, &bytes, bytes.count, 0)
            guard count > 0 else { close(); return }
            data.append(contentsOf: bytes.prefix(count))
            if let marker = data.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: data[..<marker.lowerBound], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                if data.count - marker.upperBound >= length { break }
            }
        }
        state.withLock { value in
            value.request = data; value.observer?.resume(returning: data); value.observer = nil
        }
    }
    enum Failure: Error { case setup, closed }
}
