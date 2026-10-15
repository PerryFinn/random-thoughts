import Foundation
import Synchronization

nonisolated struct AITransportTime: Sendable {
    let now: @Sendable () async -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void
    static let production = Self(now: { Date() }, sleep: { try await Task.sleep(for: .seconds($0)) })
}

nonisolated final class AIHTTPTransport: Sendable {
    private let configuration: URLSessionConfiguration
    private let time: AITransportTime
    init(configuration: URLSessionConfiguration, time: AITransportTime) {
        let copy = configuration.copy() as! URLSessionConfiguration
        copy.urlCache = nil; copy.urlCredentialStorage = nil; copy.httpCookieStorage = nil
        copy.httpShouldSetCookies = false
        // Our clock enforces phase deadlines, including effective SSE progress.
        copy.timeoutIntervalForRequest = .greatestFiniteMagnitude
        copy.timeoutIntervalForResource = .greatestFiniteMagnitude
        self.configuration = copy; self.time = time
    }
    static func production() -> AIHTTPTransport {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [:]
        return AIHTTPTransport(configuration: c, time: .production)
    }

    @concurrent func send(_ request: URLRequest, stream: (any AIResponseStream)?, service: AIServiceType) async throws -> Data {
        let streaming = stream != nil
        let started = await time.now()
        let exchange = AIHTTPExchange(configuration: configuration)
        func timer(until deadline: Date) -> Task<Void, Never> {
            Task {
                do {
                    while !Task.isCancelled {
                        let remaining = deadline.timeIntervalSince(await time.now())
                        if remaining <= 0 { exchange.cancel(.timeout); return }
                        try await time.sleep(remaining)
                    }
                } catch { }
            }
        }
        var deadline = started.addingTimeInterval(30)
        var watchdog = timer(until: deadline)
        defer { watchdog.cancel(); exchange.close() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard await time.now() < deadline else { throw AIRequestError.timeout }
            exchange.start(request)
            var data = Data(), response: HTTPURLResponse?, responseAt = started
            var parser = stream
            for try await event in exchange.events {
                let receivedAt = await time.now()
                guard receivedAt < deadline else { throw AIRequestError.timeout }
                switch event {
                case .response(let value):
                    response = value
                    responseAt = receivedAt
                    watchdog.cancel()
                    deadline = streaming ? receivedAt.addingTimeInterval(90) : started.addingTimeInterval(300)
                    watchdog = timer(until: deadline)
                case .data(let chunk):
                    data.append(chunk)
                    if let response, (200..<300).contains(response.statusCode), try parser?.append(chunk) == true {
                        watchdog.cancel()
                        deadline = receivedAt.addingTimeInterval(90)
                        watchdog = timer(until: deadline)
                    }
                    if parser?.hasTerminated == true {
                        _ = try parser?.finish()
                        return data
                    }
                }
            }
            guard await time.now() < deadline else { throw AIRequestError.timeout }
            guard let response else { throw AIRequestError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                let reason = Self.failure(status: response.statusCode, data: data, service: service)
                let retryAt = reason == .rateLimit ? Self.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: responseAt) : nil
                throw AIRequestFailure(reason: reason, retryAt: retryAt)
            }
            _ = try parser?.finish()
            return data
        } onCancel: { exchange.cancel(.cancelled) }
    }

    static func failure(status: Int, data: Data, service: AIServiceType) -> AIRequestError {
        if (300..<400).contains(status) { return .redirect }
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = value?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? error?["type"] as? String
        return failure(status: status, code: code, parameter: error?["param"] as? String, service: service)
    }
    static func failure(status: Int, code: String?, parameter: String?, service: AIServiceType) -> AIRequestError {
        switch code {
        case "invalid_api_key", "authentication_error": return .authentication
        case "model_not_found": return .model
        case "invalid_parameter", "unsupported_parameter", "unsupported_value":
            if parameter == "stream" { return .streamingUnsupported }
            if let parameter {
                let field = service == .responses ? "text.format" : "response_format"
                if parameter == field || parameter.hasPrefix(field + ".") { return .structuredUnsupported }
            }
            return .parameters
        case "invalid_request_error": return parameter != nil ? .parameters : .unknown
        case "context_length_exceeded": return .contextLimit
        case "rate_limit_exceeded": return .rateLimit
        case "insufficient_quota": return .quota
        case "server_error", "api_error": return .unavailable
        default: return status == 429 ? .serviceLimit : status >= 500 ? .unavailable : .unknown
        }
    }
    static func retryDate(_ header: String?, now: Date) -> Date? {
        guard let header else { return nil }
        let value = header.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty, value.allSatisfy(\.isNumber), let seconds = TimeInterval(value), seconds.isFinite {
            let date = now.addingTimeInterval(seconds)
            return date.timeIntervalSince1970.isFinite ? date : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; formatter.isLenient = false
        guard let date = formatter.date(from: value), date >= now else { return nil }
        return date
    }
}

private nonisolated final class AIHTTPExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: Sendable { case response(HTTPURLResponse), data(Data) }
    let events: AsyncThrowingStream<Event, any Error>
    private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
    private let finished = Mutex(false)
    private var session: URLSession!
    init(configuration: URLSessionConfiguration) {
        let stream = AsyncThrowingStream<Event, any Error>.makeStream()
        events = stream.stream; continuation = stream.continuation
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func start(_ request: URLRequest) {
        finished.withLock { value in if !value { session.dataTask(with: request).resume() } }
    }
    func close() { session.invalidateAndCancel() }
    func cancel(_ error: AIRequestError) {
        let shouldFinish = finished.withLock { value in if value { return false }; value = true; return true }
        if shouldFinish { continuation.finish(throwing: error); session.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else { cancel(.invalidResponse); completionHandler(.cancel); return }
        continuation.yield(.response(response)); completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { continuation.yield(.data(data)) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let shouldFinish = finished.withLock { value in if value { return false }; value = true; return true }
        guard shouldFinish else { return }
        if let error = error as? URLError {
            continuation.finish(throwing: error.code == .cancelled ? AIRequestError.cancelled : error.code == .timedOut ? .timeout : .network)
        } else if error != nil { continuation.finish(throwing: AIRequestError.unknown) }
        else { continuation.finish() }
    }
}
