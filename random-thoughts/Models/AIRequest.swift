import Foundation

nonisolated enum AIProbeStage: String, Sendable { case basic, streaming, structured }
nonisolated enum AIRequestIntent: Sendable { case probe(AIProbeStage), extractFacts, mergeFacts, composeReport }

// Shared business intent, not a shared wire DTO or cross-protocol parameter bag.
nonisolated struct AIRequest: Sendable {
    let intent: AIRequestIntent
    let configuration: AIServiceConfiguration
    let credential: String
    let instruction: String
    let input: String
    let schema: String?
    let streaming: Bool
}

protocol AIServiceAccess: Sendable {
    nonisolated func execute(_ request: AIRequest) async throws -> String
}

nonisolated enum AIRequestError: String, Error, Sendable {
    case network, timeout, cancelled, authentication, model, parameters, contextLimit
    case rateLimit, quota, serviceLimit, redirect, unavailable, unknown, invalidResponse, incomplete, refusal
    case unsupportedService, tokenizer, budget, needsBatching, missingInput, missingConfiguration
    case streamingUnsupported, structuredUnsupported

    var invalidatesConfiguration: Bool { [.authentication, .model, .parameters].contains(self) }
    var message: String {
        switch self {
        case .authentication: "服务明确拒绝鉴权。原正文和来源保留，请修正凭据并重新校验。"
        case .model: "服务明确说明模型不存在。原内容保留，请修正模型并重新校验。"
        case .parameters: "服务明确拒绝必要参数或协议。原内容保留，请检查配置并重新校验。"
        case .contextLimit: "服务明确报告上下文超限。原内容保留，请调整来源或请求预算。"
        case .rateLimit: "服务明确限流。原内容保留，等待后只能手动从头重试。"
        case .quota: "服务明确报告配额不足。原内容保留，请检查服务额度。"
        case .serviceLimit: "服务限制原因未知。原内容与校验资格保留，请检查服务后手动重试。"
        case .redirect: "请求端点返回重定向，已停止。请填写最终端点并重新校验。"
        case .timeout: "请求已超时。原内容保留，可手动从头重试；服务方仍可能处理或计费。"
        case .cancelled: "已取消，原正文和来源保留；服务方仍可能处理或计费。"
        case .invalidResponse, .incomplete, .refusal: "结果不完整、被拒绝或不符合六章节要求。原正文和来源保留，可手动从头重试。"
        case .unsupportedService: "此协议传输尚未接入，请显式选择已校验的 Chat Completions 配置。"
        case .tokenizer: "本地 tokenizer 初始化或计数失败，未发送工作内容。原内容保留。"
        case .budget: "请求预算无法容纳固定指令、偏好和合法输入。原内容保留，请调整 C／O。"
        case .needsBatching: "当天完整输入超出直接生成预算。原内容保留，请调整预算或明确重选来源。"
        case .missingInput: "请先确认有效会话快照；改变选择后须重新确认。"
        case .missingConfiguration: "请先显式校验配置并设为当前，生成资格与当前身份独立。"
        case .streamingUnsupported, .structuredUnsupported: "服务明确拒绝该可选能力；生成只使用已证明支持的能力。"
        case .network, .unavailable, .unknown: "请求未完成，原因未知或服务临时不可用。原内容与资格保留，可手动从头重试。"
        }
    }
    static func reason(for error: any Error) -> Self {
        (error as? AIRequestFailure)?.reason ?? error as? Self ?? (error is CancellationError ? .cancelled : .unknown)
    }
}

// No free-text service errors, URLs or response bodies leave the transport.
nonisolated struct AIRequestFailure: Error, Sendable {
    let reason: AIRequestError
    let retryAt: Date?
}

nonisolated struct AIValidationEvent: Sendable {
    enum Result: String, Sendable { case success, failure, unfinished, cancelled }
    let service: AIServiceType
    let stage: AIProbeStage
    let result: Result
    let capability: AIServiceCapability
}
