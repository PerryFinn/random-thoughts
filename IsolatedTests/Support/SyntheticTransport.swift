import Foundation
import Synchronization

final class SyntheticTransport: Sendable {
    let endpoint = URL(string: "https://\(UUID().uuidString).fixture.invalid/points")!
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticURLProtocol.self]
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
        respond(with: Self.points)
    }

    var requests: [URLRequest] {
        SyntheticURLProtocol.routes.withLock { $0[endpoint]?.requests ?? [] }
    }

    func respond(with data: Data, statusCode: Int = 200) {
        SyntheticURLProtocol.routes.withLock {
            let requests = $0[endpoint]?.requests ?? []
            $0[endpoint] = .init(result: .success(data), statusCode: statusCode, requests: requests)
        }
    }

    func fail() {
        SyntheticURLProtocol.routes.withLock {
            let requests = $0[endpoint]?.requests ?? []
            $0[endpoint] = .init(result: .failure(URLError(.cannotConnectToHost)), requests: requests)
        }
    }

    func close() {
        session.invalidateAndCancel()
        SyntheticURLProtocol.routes.withLock { $0[endpoint] = nil }
    }

    // Entirely synthetic, matching the current public IntelligenceResponse JSON fields.
    static let points = Data(
        #"{"points":[{"model":"synthetic","effort":"max","iq":42}]}"#.utf8
    )
}

private final class SyntheticURLProtocol: URLProtocol, @unchecked Sendable {
    struct Route: Sendable {
        var result: Result<Data, URLError>
        var statusCode = 200
        var requests: [URLRequest] = []
    }

    // URLProtocol callbacks can arrive on URLSession threads. All shared state uses this lock.
    static let routes = Mutex<[URL: Route]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let route = Self.routes.withLock { routes -> Route? in
            guard let url = request.url, routes[url] != nil else { return nil }
            routes[url]?.requests.append(request)
            return routes[url]
        }
        guard let route, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch route.result {
        case .success(let data):
            let response = HTTPURLResponse(
                url: url, statusCode: route.statusCode, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
