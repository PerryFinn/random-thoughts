# 首版 AI 协议兼容边界

> 调研日期：2026-08-14  
> 决策票：[验证首版 AI 协议兼容边界](https://github.com/PerryFinn/random-thoughts/issues/5)

## 结论

首版应实现三个独立适配器，而不是把三类服务伪装成一套线协议：

1. **OpenAI Responses API**：固定官方 API 根地址，使用官方 Responses 协议。
2. **OpenAI Responses-compatible 自定义端点**：API 根地址可配置，只承诺本文定义且经过“测试配置”验证的最小 Responses 子集。
3. **Anthropic Messages API**：固定官方 API 根地址，使用官方 Messages 协议。

产品和代码中应使用官方的复数名称 **Responses API** 与 **Messages API**；“Response API”或“Message API”不作为正式名称。OpenAI 官方将直接模型请求入口称为 Responses，并把创建操作定义为 `POST /responses`（完整官方地址为 `/v1/responses`）；Anthropic 将创建消息定义为 `POST /v1/messages`。[OpenAI API overview](https://developers.openai.com/api/reference/overview)、[OpenAI Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create)、[Anthropic Create a Message](https://platform.claude.com/docs/en/api/messages/create)

“OpenAI-compatible”不是可以据名称推导能力的通用标准。本项目必须把它收窄为自己的 **Responses-compatible conformance profile**：基础文本生成是必需能力，SSE 流式与 JSON Schema 结构化输出是可选能力，只有探测成功后才能启用。该结论是根据 OpenAI 官方只对其 `v1` REST API 给出兼容性承诺、且允许未来增加字段和流事件所作的产品推论；它不代表 OpenAI 为第三方兼容实现提供认证。[OpenAI backwards compatibility](https://developers.openai.com/api/reference/overview#backwards-compatibility)

首版不支持 Chat Completions 兼容接口。将“自定义端点”标为 OpenAI Responses-compatible，比笼统的 OpenAI-compatible 更诚实，也避免把只实现 `/v1/chat/completions` 的服务误判为可用。

## 首版共同抽象

共同抽象只覆盖生成日报需要的语义，不透传厂商请求对象：

```swift
struct AIServiceCapabilities {
    var streaming: Bool
    var structuredOutput: Bool
    var remoteCancellation: Bool
}

struct DailyReportGenerationRequest {
    var model: String
    var systemInstruction: String
    var input: String
    var maxOutputTokens: Int
    var outputMode: OutputMode // plainText 或 dailyReportSchema
}

enum GenerationEvent {
    case started(requestID: String?)
    case textDelta(String)
    case completed(GenerationResult)
}

struct GenerationResult {
    var text: String
    var finish: FinishState
    var usage: TokenUsage?
    var providerRequestID: String?
}

enum FinishState {
    case completed
    case truncated
    case refused(String?)
    case cancelled
    case failed(AIServiceError)
}
```

以下内容不应进入共同请求：`previous_response_id`、provider conversation、工具调用、reasoning effort、prompt cache、OpenAI organization/project、Anthropic beta headers。首版日报是单次、无工具、文本输入/文本输出任务；把厂商高级特性放进共同接口会让接口虚假对称。

所有响应解析器都必须：

- 按 `type` 分派联合类型，而不是假定数组第一个元素一定是正文；
- 忽略未知 JSON 字段和未知 SSE 事件，同时保留对已知终止/错误事件的严格检查；OpenAI 明确把新增字段和流事件视为向后兼容改动，Anthropic 也要求客户端优雅处理未知事件。[OpenAI backwards compatibility](https://developers.openai.com/api/reference/overview#backwards-compatibility)、[Anthropic streaming: other events](https://platform.claude.com/docs/en/build-with-claude/streaming#other-events)
- 只在成功终止后把草稿标记为“已生成”；截断、拒绝、取消和失败均是不同状态，不能都折叠成网络错误；
- 将用量视为可选遥测，不以用量字段是否存在判断生成成功。

## 请求与响应映射

| 语义 | OpenAI Responses | Anthropic Messages |
| --- | --- | --- |
| 创建 | `POST /v1/responses` | `POST /v1/messages` |
| 模型 | `model` | `model` |
| 系统指令 | 顶层 `instructions`，或 input 中的 developer/system message | 顶层 `system`；Messages 文档明确指出消息列表中不使用 system role |
| 用户内容 | `input` 字符串或 input item 列表 | `messages: [{"role":"user","content": ...}]` |
| 输出上限 | `max_output_tokens`，包括可见输出与 reasoning tokens | 必填 `max_tokens`；模型可在达到上限前停止 |
| 流式 | `stream: true` | `stream: true` |
| 结构化输出 | `text.format = {type:"json_schema", name, schema, strict}` | `output_config.format = {type:"json_schema", schema}` |
| 正文 | 遍历 `output` 中 `type == "message"` 的 content，再取 `type == "output_text"` 的 `text` | 遍历 `content`，拼接 `type == "text"` 的 `text` |
| 完成原因 | `status`，并检查 `error`、`incomplete_details` 和 refusal content | `stop_reason`、`stop_sequence` |
| 用量 | `usage.input_tokens`、`usage.output_tokens` 等 | `usage`；官方提示其 token 计数不一定与可见内容一一对应 |

依据：[OpenAI create request and Response object](https://developers.openai.com/api/reference/resources/responses/methods/create)、[Anthropic Messages request and Message object](https://platform.claude.com/docs/en/api/messages/create)

OpenAI SDK 的 `output_text` 是聚合 `output` 数组的 **SDK-only convenience property**，直接用 `URLSession` 实现时不能依赖它；应用必须解析线上的 `output` 联合类型。[OpenAI Response object](https://developers.openai.com/api/reference/resources/responses/methods/create#returns)

为了避免引入服务端会话状态和不必要的数据保留，OpenAI 请求应显式发送 `store: false`，且首版不使用 `previous_response_id` 或 `conversation`。Anthropic Messages 本身按请求携带历史，是无状态的多轮接口；首版只发送这次日报所需的输入。[OpenAI `store` parameter](https://developers.openai.com/api/reference/resources/responses/methods/create)、[Anthropic Messages API](https://platform.claude.com/docs/en/api/messages/create)

## 流式输出

### OpenAI Responses

OpenAI 通过 `stream: true` 使用 SSE，并采用语义化事件。首版解析器至少处理：

- `response.created`：记录 response/request 标识；
- `response.output_text.delta`：追加正文；
- `response.completed`：从最终 Response 校验 `status` 并完成；
- `response.incomplete`、`response.failed`：分别映射为截断和失败；
- `error`：映射为协议流错误；
- 其他事件：忽略，不中断正文聚合。

官方流式指南列出 `response.created`、`response.output_text.delta`、`response.completed` 和 `error`，完整事件集合由 Responses 流事件参考定义；官方 SDK 的 OpenAPI 生成类型也包含 completed、failed、incomplete 和 error，而没有前台流的 `response.cancelled` 事件。本地用户取消由应用自身映射。[OpenAI streaming responses](https://developers.openai.com/api/docs/guides/streaming-responses)、[OpenAI streaming events](https://developers.openai.com/api/reference/resources/responses#streaming-events)、[OpenAI SDK ResponseStreamEvent](https://github.com/openai/openai-python/blob/main/src/openai/types/responses/response_stream_event.py)

### Anthropic Messages

Anthropic 的 SSE 是一个需要聚合的事件序列：

1. `message_start`；
2. 每个内容块的 `content_block_start`、零个或多个 `content_block_delta`、`content_block_stop`；
3. 一个或多个 `message_delta`；
4. `message_stop`。

首版只把 `content_block_delta.delta.type == "text_delta"` 的 `text` 暴露成正文增量；仍需消费其他已知事件以拿到最终 `stop_reason` 和 usage。`ping` 是保活事件，不是正文。Anthropic 还可能在 HTTP 已返回 200 后发送 `event: error`，因此“HTTP 200”不能提前当作成功。[Anthropic streaming event flow](https://platform.claude.com/docs/en/build-with-claude/streaming#event-types)、[Anthropic streaming error events](https://platform.claude.com/docs/en/build-with-claude/streaming#error-events)

流式解析应按字节增量实现标准 SSE framing，不能假定一次网络回调恰好对应一个 JSON 事件，也不能逐 delta 解析尚未完整的结构化 JSON。日报编辑区可以实时显示累积文本，但只有终止事件校验通过后才进入可保存的完整草稿状态。

## 结构化输出

两家官方接口都支持 JSON Schema，但请求位置、支持模型和边缘情况不同：

- OpenAI Responses 使用 `text.format`；`type` 为 `json_schema`，并包含 `name`、`schema` 与建议启用的 `strict: true`。官方说明 Structured Outputs 从 GPT-4o 及更新模型开始提供，旧模型不一定支持。[OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- Anthropic Messages 使用 `output_config.format`，不是已经迁移中的旧 `output_format`；官方列出的支持模型范围会变化，不能从“Anthropic”类型推断任意模型都支持。[Anthropic Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- 两者都只支持 JSON Schema 的子集，应维护一份两边都能表达的简单日报 schema：对象、字符串、字符串数组、required、`additionalProperties: false`；不依赖复杂条件、引用或正则约束。

结构化输出不能让应用跳过终止状态检查：

- OpenAI 在 refusal 或 `status == "incomplete"`（例如 `max_output_tokens`）时可能不返回符合 schema 的结果；拒绝通过 content part 的 `type == "refusal"` 表达。[OpenAI Structured Outputs edge cases](https://developers.openai.com/api/docs/guides/structured-outputs#how-to-use-structured-outputs-with-textformat)
- Anthropic 拒绝仍返回 HTTP 200、`stop_reason == "refusal"`，且输出可能不符合 schema；`stop_reason == "max_tokens"` 时 JSON 也可能不完整。[Anthropic Structured Outputs invalid outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#invalid-outputs)

首版的**基础能力必须是纯文本日报**。结构化输出仅在适配器确认模型支持时启用；否则让模型直接输出 Markdown，并把整个 Markdown 当作可编辑草稿。这样，结构化能力缺失不会让一个本来能生成文本的自定义端点完全不可用。

## 错误模型与重试

应用应归一化为以下错误类别：

```text
invalidConfiguration
authentication
permission
invalidRequest
payloadTooLarge
rateLimited(retryAfter)
quotaOrBilling
providerUnavailable
timeout
network
protocolMismatch
unsupportedCapability
cancelledByUser
unknown
```

每个错误尽量保留：HTTP status、厂商 `type`/`code`、安全可展示的 message、request ID、`Retry-After`，但不得记录 API Key 或聊天正文。

OpenAI 官方文档区分 401、403、429、500、503 等状态，并要求限流时遵循 `Retry-After`；官方 SDK 从顶层 `error` 中读取 `message`、`type`、`code`、`param`，从 `x-request-id` 读取请求标识。[OpenAI error codes](https://developers.openai.com/api/docs/guides/error-codes)、[OpenAI SDK APIError source](https://github.com/openai/openai-node/blob/master/src/core/error.ts)、[OpenAI request IDs](https://developers.openai.com/api/reference/overview#debugging-requests)

Anthropic 错误体为顶层 `type: "error"`、内部 `error.type`/`error.message`，并带 `request_id`；状态包括 400、401、403、404、413、429、500、529 等。每个响应还有 `request-id` header，且 SSE 中可能出现流内错误。[Anthropic API errors](https://platform.claude.com/docs/en/api/errors)

重试策略：

- 只对网络瞬时失败、429 和可恢复 5xx/529 做有限次指数退避，并遵循 `Retry-After`；
- 401、403、无余额/账单、协议不匹配、无效请求不自动重试；
- 一旦已经显示任何正文增量，不自动重放整次生成，因为会产生重复计费和语义不同的第二份日报；提示用户显式“重新生成”；
- request ID 随错误展示在“详情”中，便于供应商支持定位。

## 取消

首版“取消生成”的共同语义是：取消本地 `URLSessionTask`/SSE 消费，停止更新草稿，并把结果标为 `cancelledByUser`。

OpenAI 的资源级 `POST /responses/{response_id}/cancel` **只适用于以 `background: true` 创建的 Response**。首版使用前台请求，不应为了远程取消而引入 background、轮询和额外兼容要求。[OpenAI Cancel a response](https://developers.openai.com/api/reference/resources/responses/methods/cancel)

Anthropic 普通 Messages 参考只提供创建消息和 token counting，没有单条 Message 的资源级取消接口；官方 Python SDK 的流管理器退出或 `stream.close()` 会取消客户端请求。因此，对两家首版前台请求都采用传输层取消。传输层取消不能承诺服务端已停止计算或不会计费，UI 文案应是“已停止等待并丢弃本次结果”，而不是“供应商已撤销请求”。[Anthropic Messages API](https://platform.claude.com/docs/en/api/messages)、[Anthropic Python SDK streaming helpers](https://github.com/anthropics/anthropic-sdk-python/blob/main/helpers.md#streaming-responses)

`remoteCancellation` 在首版三个适配器中均为 `false`。

## 鉴权与配置项

### OpenAI 官方

- 用户输入：API Key、模型；
- 固定地址：`https://api.openai.com/v1`；
- header：`Authorization: Bearer <key>`；
- API Key 存入 Keychain，其他非秘密配置存应用设置；
- 首版不暴露 organization/project 选择，避免把企业路由扩进基础配置。

OpenAI 官方使用 Bearer 鉴权，并可选用 organization/project header。[OpenAI authentication](https://developers.openai.com/api/reference/overview#authentication)

### OpenAI Responses-compatible

- 用户输入：API 根地址、API Key（允许为空以支持无需鉴权的本机端点）、模型；
- 根地址语义：用户填写 API root，例如 `https://example.com/v1`，应用固定追加 `/responses`；
- API Key 非空时发送 `Authorization: Bearer <key>`；
- 首版不支持任意自定义 header、OAuth、云厂商签名、客户端证书或 Chat Completions 路径；
- UI 帮助文案必须明确“要求兼容 Responses API，不是 Chat Completions”。

### Anthropic 官方

- 用户输入：API Key、模型；
- 固定地址：`https://api.anthropic.com`；
- headers：`x-api-key: <key>`、固定 `anthropic-version: 2023-06-01`、`content-type: application/json`；
- API 版本由应用固定并随版本升级，不让用户自由填写；
- API Key 存入 Keychain。

Anthropic 官方要求 `x-api-key` 或短期 Bearer token 二选一，并要求 `anthropic-version` 与 content type；首版只支持用户已决定的 API Key 路径。[Anthropic API overview: authentication](https://platform.claude.com/docs/en/api/overview#authentication)

## Responses-compatible 最小 conformance profile

一个自定义端点只有满足以下**必需子集**，应用才显示“基本生成可用”：

### 必需请求

- 接受 `POST {apiRoot}/responses`；
- 接受 JSON `model`、`input`、`max_output_tokens`、`stream: false`；
- 容忍 `instructions` 与 `store: false`；
- API Key 非空时接受 OpenAI Bearer header。

### 必需成功响应

- HTTP 2xx 与 JSON body；
- 存在字符串 `id`；
- `status == "completed"`；
- `output` 至少有一个 `type == "message"` 的 item；
- 该 item 的 `content` 至少有一个 `type == "output_text"` 且 `text` 为字符串的 part；
- 可以增加未知字段，解析器忽略它们；`usage` 可省略。

### 必需失败行为

- 非 2xx 必须被当作失败，不能把错误 body 当正文；
- 推荐返回 OpenAI error envelope：`{"error":{"message":...,"type":...,"code":...,"param":...}}`；
- 若端点返回非 JSON 或非标准错误体，应用仍以 HTTP status 和截断后的安全文本展示通用错误，但不能声称提供精细错误分类。

错误 envelope 不作为“测试配置”的破坏性探测项，因为故意制造无效模型或高负载请求既不可靠也可能产生副作用；运行时遇到错误时再记录实际兼容程度。

### 可选能力

**流式**只有在端点接受 `stream: true`、以 SSE 返回 `response.output_text.delta`，并以 `response.completed` 携带可校验的最终 Response 结束时才标为支持。

**结构化输出**只有在端点接受 OpenAI `text.format.type == "json_schema"`，且对应用的小型探测 schema 返回有效、符合 schema 的 JSON 时才标为支持。只返回“看起来像 JSON”的文本不算结构化输出支持。

**远程取消**首版不探测、不承诺。

### “测试配置”流程

保存服务配置前由用户显式点击“测试”，并告知会发送极小请求、可能产生少量费用：

1. 必需：非流式纯文本探测，验证 endpoint、鉴权、模型与最小成功响应；失败则配置不可保存为可用状态。
2. 可选：流式探测；失败只关闭 `streaming` capability，基础生成仍可用。
3. 可选：简单对象 schema 探测；失败只关闭 `structuredOutput` capability。

探测结果连同“最后验证时间”和配置指纹保存；API root、模型或鉴权配置变化后使结果失效。不能通过 `GET /models` 或模型名称猜测能力，因为两家官方文档都表明能力随模型而异，而第三方实现更无统一保证。[OpenAI model catalog](https://developers.openai.com/api/docs/models)、[Anthropic model overview](https://platform.claude.com/docs/en/about-claude/models/overview)

## 明确不承诺的范围

- `/v1/chat/completions`、legacy completions；
- Azure OpenAI、Amazon Bedrock、Google Vertex AI 等不同鉴权/路径的云平台变体；
- Ollama、LM Studio 或任意供应商仅凭“OpenAI-compatible”宣传即可工作；
- 工具调用、图片/音频/file input、reasoning/thinking 输出、prompt caching；
- provider-side conversation、Responses background mode、webhook、batch；
- 自动列出模型、价格计算、精确 token 计费；
- 任意自定义 headers、OAuth、mTLS 或云签名；
- 对取消后的服务端停止执行或退款作保证。

## 对后续规格的决策摘要

1. 设置下拉项命名为“OpenAI”“OpenAI Responses-compatible”“Anthropic”；官方协议名称在说明中使用 Responses API / Messages API。
2. 三个 provider adapter 共享业务语义，不共享厂商 DTO；直接使用 `URLSession` 时按官方线协议解码。
3. 纯文本生成是共同最低能力；结构化输出和流式是 capability，不是 provider 类型的必然属性。
4. 自定义端点只支持本文的 `/v1/responses` 子集；Chat Completions 与云平台变体排除在首版之外。
5. 用户主动“测试配置”决定自定义端点能力；模型或地址变化后重新测试。
6. UI 取消只承诺终止本地等待并丢弃本次结果；首版不使用后台 Response，也不承诺远程撤销。
7. 解析器必须区分 completed、truncated、refused、cancelled、failed，并保留 request ID 供排错。
