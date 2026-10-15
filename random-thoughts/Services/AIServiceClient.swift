import Foundation

nonisolated struct AIServiceClient: AIServiceAccess {
    let transport: AIHTTPTransport
    func execute(_ request: AIRequest) async throws -> String {
        switch request.configuration.service {
        case .chatCompletions: try await ChatCompletionsAdapter(transport: transport).execute(request)
        case .responses: try await ResponsesAdapter(transport: transport).execute(request)
        case .messages: try await MessagesAdapter(transport: transport).execute(request)
        }
    }
    static func serializedFormat(_ schema: String, configuration: AIServiceConfiguration) throws -> String {
        switch configuration.service {
        case .chatCompletions: return try ChatCompletionsAdapter.serializedFormat(schema)
        case .responses: return try ResponsesAdapter.serializedFormat(schema)
        case .messages:
            guard case .messages(let defaults) = configuration.defaults else { throw AIRequestError.parameters }
            return try MessagesAdapter.serializedFormat(schema, defaults: defaults)
        }
    }
}
