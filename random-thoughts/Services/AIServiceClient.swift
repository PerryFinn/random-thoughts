import Foundation

nonisolated struct AIServiceClient: AIServiceAccess {
    let transport: AIHTTPTransport
    func execute(_ request: AIRequest) async throws -> String {
        switch request.configuration.service {
        case .chatCompletions: try await ChatCompletionsAdapter(transport: transport).execute(request)
        case .responses: try await ResponsesAdapter(transport: transport).execute(request)
        case .messages: throw AIRequestError.unsupportedService
        }
    }
    static func serializedFormat(_ schema: String, service: AIServiceType) throws -> String {
        switch service {
        case .chatCompletions: try ChatCompletionsAdapter.serializedFormat(schema)
        case .responses: try ResponsesAdapter.serializedFormat(schema)
        case .messages: throw AIRequestError.unsupportedService
        }
    }
}
