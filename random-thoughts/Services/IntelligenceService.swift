import Foundation

struct IntelligenceService: Sendable {
    nonisolated static let endpoint = URL(
        string: "https://codexradar.com/data/intelligence-efficiency.json?v=20260804-activity24h"
    )!

    private let session: URLSession
    private let endpoint: URL

    nonisolated init(session: URLSession, endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    nonisolated func fetch() async throws -> IntelligenceResponse {
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw IntelligenceServiceError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(IntelligenceResponse.self, from: data)
        } catch {
            throw IntelligenceServiceError.invalidData(error)
        }
    }
}

enum IntelligenceServiceError: LocalizedError {
    case invalidResponse
    case invalidData(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器返回了无效响应"
        case .invalidData:
            "无法解析服务器数据"
        }
    }
}
