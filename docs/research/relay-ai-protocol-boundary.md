# 可配置中转地址的三类 AI 协议适配器边界

> 调查日期：2026-08-20  
> 范围：OpenAI Chat Completions API、OpenAI Responses API、Anthropic Messages API；目标是让三类适配器都可连接用户指定的中转站端点。  
> 证据边界：OpenAI 事实只引用 OpenAI 官方文档，Anthropic 事实只引用 Claude Platform 官方文档。官方文档描述各自官方服务；对中转站的任何兼容性判断均是本文明确标注的设计推论。

## 结论

1. 首版的三种类型应是三个**协议适配器**，正式名称分别为 **OpenAI Chat Completions API**、**OpenAI Responses API** 和 **Anthropic Messages API**，而不是“两个官方服务 + 一个 Responses-compatible 服务”。三者的创建路径、请求与响应 JSON、SSE 事件以及结构化输出字段都不同，不能共享 wire DTO 或解析器。
2. 三种适配器都应保存用户可配置的请求地址，以便连接中转站。固定 `api.openai.com` 或 `api.anthropic.com` 只能作为官方地址示例或默认值，不能再成为类型定义的一部分。这是本项目的新产品约束，不是官方文档对第三方中转站的保证。
3. “兼容”不是第四种服务类型，也不应只修饰 Responses。一个中转地址是否兼容某个适配器，只能由“端点 + 鉴权方式 + 版本头 + 模型 + 实际请求字段”的探测证据确认。
4. 日报纯文本最低子集可以在三个适配器内各自保持很小，但不能做成一个公共请求对象。应用层可以共享“指令文本、用户输入、模型标识、是否流式、期望结构化结果”等意图；适配器必须分别编码和解析。

## 一、官方名称与创建路径

| 适配器名称 | 官方创建操作 | 官方完整地址示例 | 若 `API root` 已含 `/v1`，追加的相对路径 |
| --- | --- | --- | --- |
| OpenAI Chat Completions API | `POST /chat/completions` | `https://api.openai.com/v1/chat/completions` | `chat/completions` |
| OpenAI Responses API | `POST /responses` | `https://api.openai.com/v1/responses` | `responses` |
| Anthropic Messages API | `POST /v1/messages` | `https://api.anthropic.com/v1/messages` | `messages` |

OpenAI 的 [Create chat completion](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create) 页面使用 “Chat Completions” 作为资源名，并给出 `https://api.openai.com/v1/chat/completions` 的 HTTP 示例。OpenAI 的 [Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create) 页面将 Responses 创建操作列为 `POST /responses`；官方平台示例给出完整的 `https://api.openai.com/v1/responses` 地址，[API Overview](https://developers.openai.com/api/reference/overview#backwards-compatibility) 说明当前 REST API 主版本为 `v1`。Anthropic 的 [Create a Message](https://platform.claude.com/docs/en/api/messages/create) 明确列出 `POST /v1/messages`。

这里应采用官方复数名称 **Chat Completions**；它不是 OpenAI 另列为 legacy 的 `POST /v1/completions` 文本补全接口。

这里的“完整地址示例”是官方服务事实。把 host 或整个 endpoint 改成中转站地址，是应用配置能力；官方资料没有为第三方地址定义一致性认证或 conformance profile。

## 二、日报纯文本最低请求与响应

### 1. OpenAI Chat Completions API

适合纯文本探测的最小请求意图是：

```json
{
  "model": "用户填写的精确模型标识",
  "messages": [
    {"role": "user", "content": "返回一个很短的纯文本结果"}
  ]
}
```

`model` 与 `messages` 是核心字段；纯文本内容可直接使用字符串。若正式日报希望把系统指令与用户内容分离，Chat Completions 使用 `developer` 或 `system` 消息，而不是 Responses 的 `instructions` 或 Anthropic 的顶层 `system`。官方参考还提醒，不同模型对消息角色和参数的支持可能不同，因此最低探测只使用一个 `user` 文本消息能减少无关变量。[Create chat completion](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)

非流式响应是 `chat.completion` 对象；可见文本位于 `choices[].message.content`，结束原因位于 `choices[].finish_reason`。适配器不能把整个响应当成一段字符串，也不能假设 `content` 永远非空，因为拒绝或工具调用会产生其他形态。[Create chat completion — response](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create#returns)

与日报相关、但不属于最低纯文本请求的协议专属字段包括：

- `temperature`：顶层字段；模型可能拒绝某些组合。
- `reasoning_effort`：顶层蛇形字段。
- `max_completion_tokens`：当前输出上限字段；旧 `max_tokens` 已被标为 deprecated。
- `response_format`：结构化输出配置。
- `stream`：是否启用 SSE。

### 2. OpenAI Responses API

适合纯文本探测的最小请求意图是：

```json
{
  "model": "用户填写的精确模型标识",
  "input": "返回一个很短的纯文本结果"
}
```

`input` 可以直接是字符串；该形式等价于 `user` 角色文本。正式日报若要分开高优先级指令，可使用顶层 `instructions`，但它不是 Chat Completions 的消息数组，也不是 Anthropic 的 `system` 字段。[Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create)

非流式 HTTP 响应是 `Response` 对象。原始 wire 响应的文本必须从 `output` 数组内的有类型输出项读取：通常是 `message` 项下 `content` 数组中的 `output_text` 内容块。顶层 `output_text` 是 Python/JavaScript SDK 的聚合便利属性，官方参考明确标为 **SDK-only**，直接 HTTP 适配器不能依赖它。[Create a model response — response](https://developers.openai.com/api/reference/resources/responses/methods/create#returns)

与日报相关、但不属于最低纯文本请求的协议专属字段包括：

- `temperature`：顶层字段；实际模型支持仍需验证。
- `reasoning.effort`：嵌套字段，不能复用 Chat Completions 的 `reasoning_effort` 编码。
- `max_output_tokens`：顶层输出上限字段。
- `text.format`：结构化输出配置。
- `stream`：是否启用 SSE。

### 3. Anthropic Messages API

适合纯文本探测的最小请求意图是：

```json
{
  "model": "用户填写的精确模型标识",
  "max_tokens": 64,
  "messages": [
    {"role": "user", "content": "返回一个很短的纯文本结果"}
  ]
}
```

Messages 的 `model`、`max_tokens` 和 `messages` 是纯文本生成所需的核心字段；`max_tokens` 与两个 OpenAI 接口的可选输出上限不同。消息内容可直接是字符串，等价于单个 `text` 内容块。系统指令使用顶层 `system`；Messages 输入消息没有 `system` 角色。[Create a Message](https://platform.claude.com/docs/en/api/messages/create)

非流式响应是 `Message` 对象。可见文本位于 `content[]` 中 `type: "text"` 的内容块；适配器还必须检查 `stop_reason`，不能假设所有内容块都是文本。[Using the Messages API](https://platform.claude.com/docs/en/build-with-claude/working-with-messages) [Stop reasons and fallback](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)

与日报相关、但不属于最低纯文本请求的协议专属字段包括：

- `temperature`：顶层字段，范围与模型兼容规则不同于 OpenAI。
- `thinking` 与 `output_config.effort`：思考模式和投入控制。
- `output_config.format`：结构化输出配置。
- `stream`：是否启用 SSE。

### 4. 最低子集的产品含义（设计推论）

纯文本基础探测可以把日报模板、生成偏好和极短输入合并成一个用户文本，从而只验证最小协议面。若正式生成一定会分别发送 `developer`、`instructions` 或 `system`，那么“已校验”探测也必须发送这些字段，否则探测成功不足以证明正式请求可用。最低探测与完整调用配置探测可以是两个证据阶段，但不能用前者冒充后者。

## 三、流式响应不是同一种 SSE

三者都通过 `stream: true` 请求 SSE，但事件负载不同：

| 适配器 | 主要文本增量 | 完成判断 | 解析重点 |
| --- | --- | --- | --- |
| Chat Completions | `chat.completion.chunk` 的 `choices[].delta.content` | choice 的 `finish_reason`，流末尾还有 `[DONE]` 语义 | 增量嵌在 choices/delta 结构中 |
| Responses | `response.output_text.delta` 的 `delta` | `response.completed`；还需处理 failed/incomplete/error 事件 | 每个事件有语义化 `type`，不能按 Chat chunk 解码 |
| Anthropic Messages | `content_block_delta` 内 `text_delta.text` | `message_delta` 给出 stop reason，最后 `message_stop` | 有 `message_start`、内容块 start/delta/stop、ping 和流内 error |

Chat Completions 的官方 [streaming events reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events) 将事件定义为 `chat.completion.chunk`，文本位于 `choices[].delta.content`。Responses 的官方 [streaming events reference](https://developers.openai.com/api/reference/resources/responses/streaming-events) 定义了 `response.output_text.delta` 等有类型事件。Anthropic 的 [Streaming Messages](https://platform.claude.com/docs/en/build-with-claude/streaming) 给出完整事件顺序，并明确客户端应容忍未来新增的未知事件类型。

因此，“支持流式”只能作为三个适配器共享的应用层能力名，不能对应一个共享 SSE 解码器。探测成功至少要证明：收到合法事件序列、提取到预期极短文本、观察到合法终止，而不只是 HTTP 连接返回 `text/event-stream`。

## 四、结构化输出字段与结果位置

| 适配器 | 请求字段 | JSON Schema 形状 | 结果读取位置 |
| --- | --- | --- | --- |
| Chat Completions | `response_format` | `{ "type": "json_schema", "json_schema": { "name", "schema", "strict" } }` | `choices[].message.content` 中的 JSON 文本 |
| Responses | `text.format` | `{ "type": "json_schema", "name", "schema", "strict" }` | `output[]` 的 `output_text` 内容块 |
| Anthropic Messages | `output_config.format` | `{ "type": "json_schema", "schema": ... }` | `content[]` 的 `text` 内容块 |

Chat Completions 的字段形状来自 [Create chat completion — response_format](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create#chat-create-response_format)。Responses 把相同意图放在 `text.format`，见 [Create a model response — text](https://developers.openai.com/api/reference/resources/responses/methods/create)。Anthropic 使用 `output_config.format`，而且官方说明结构化 JSON 仍返回在文本内容块中，见 [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)。

这些是协议形状，不是“任意模型都支持结构化输出”的保证。OpenAI 的创建参考明确指出参数支持因模型而异；Anthropic 也公布了结构化输出的模型可用范围和 JSON Schema 限制。对中转站，结构化探测最多能证明该端点、模型和 schema 组合在测试时被接受并返回了符合最低契约的 JSON。它不能证明该中转站实现了官方服务的所有 schema 关键字、拒绝语义或未来行为。

## 五、默认鉴权与版本头

### 官方协议事实

| 适配器 | 默认 API-key 鉴权 | 内容类型 | 版本表达 |
| --- | --- | --- | --- |
| OpenAI Chat Completions | `Authorization: Bearer <key>` | `Content-Type: application/json` | REST 主版本在 URL 的 `/v1` 中；没有对应 Anthropic 的必填版本请求头 |
| OpenAI Responses | `Authorization: Bearer <key>` | `Content-Type: application/json` | 同上 |
| Anthropic Messages | `x-api-key: <key>` | `content-type: application/json` | 必填 `anthropic-version`；官方当前示例为 `2023-06-01` |

OpenAI 的 [API authentication](https://developers.openai.com/api/reference/overview#authentication) 规定 Bearer credential；可选的 `OpenAI-Organization` 和 `OpenAI-Project` 只在对应账户场景使用，不属于日报最低子集。Anthropic 的 [Authentication](https://platform.claude.com/docs/en/manage-claude/authentication) 与 [Versions](https://platform.claude.com/docs/en/api/versioning) 分别规定 API key 的 `x-api-key` 头和必填 `anthropic-version` 头。

### 中转站推论

- 选择某个协议适配器时，默认应发送该协议的官方鉴权与版本头；这样“兼容该协议”才有可测试的明确含义。
- 某些中转站可能要求不同的 key header、Bearer 方案、额外 header，或忽略官方版本头。官方资料不能替这些行为背书。如果产品需要支持它们，鉴权方案或附加 header 必须成为显式配置，而不能根据 host 名静默猜测。
- API key 是否允许为空也是中转站扩展决策；官方 OpenAI/Anthropic API key 调用都要求凭据。允许空 key 可以提升本地代理兼容性，但不能描述成官方协议事实。

## 六、`API root` 与完整 endpoint 的组合方式

### 官方事实

官方文档只建立三条官方完整创建地址及其请求协议，没有规定第三方中转站必须采用相同 host、相同前缀或相同路径。

### 两种可实现的配置契约（设计推论）

**契约 A：只保存 `API root`**

- 将 root 定义为已经包含版本/代理前缀、但不包含创建操作后缀的 URL，例如 `https://relay.example/openai/v1`。
- 规范化尾斜杠后，按适配器追加 `chat/completions`、`responses` 或 `messages`。
- 官方 root 示例均为 `https://api.openai.com/v1` 或 `https://api.anthropic.com/v1`。
- 若用户误填已经包含完整操作后缀的 URL，应明确报错，不能再次追加。

这个契约简单，但只能连接保留标准路径后缀的中转站。

**契约 B：保存完整“请求端点”**

- 用户输入最终接收 `POST` 的完整 URL；适配器不再追加路径。
- 官方默认值分别是三条官方完整地址。
- 该契约可以连接采用任意代理前缀或非标准路由的中转站，最符合“填写 endpoint 与中转站对接”的目标。

如果产品希望同时支持两种输入，必须把模式显式建模为 tagged union，例如 `apiRoot(URL)` 与 `fullEndpoint(URL)`；不要对一个无标签 URL 通过末尾字符串静默猜测。解析后的**最终完整 endpoint**应进入校验基线。若只保留一个用户字段，为最大化中转站兼容面，本文建议采用契约 B，并把字段明确命名为“请求端点”而不是“API root”。这是产品建议，不是官方要求。

## 七、中转站能力只能由探测证明

对每一种配置，能力证据都应绑定以下元组：

```text
适配器协议版本
+ 最终完整 endpoint
+ 实际鉴权/版本头方案
+ 凭据版本
+ 精确模型标识
+ 实际发送的服务专属生成默认值
+ 探测契约版本
```

建议继续使用三个独立探测：

1. **基础纯文本**：验证该适配器的最小请求和非空文本响应；它是“已校验”的门槛。
2. **流式**：使用同一配置加 `stream: true`，验证该适配器自己的事件序列、文本增量和合法终止。
3. **结构化输出**：发送一个极小 JSON Schema，验证 HTTP/SSE 成功、按适配器正确提取结果，并由本地 JSON Schema 校验器复核。

探测成功只能表述为：在时间 T，该 endpoint 以给定头、模型和字段组合接受了某个协议形状，并返回满足本应用最低解析契约的结果。不能进一步宣称中转站“完整兼容 OpenAI/Anthropic”、被省略字段受支持、参数语义等同官方服务，或未来仍保持兼容。

## 八、对原 #5 结论的影响

### 被新范围明确推翻

1. **排除 Chat Completions**：旧范围只研究 Responses 与 Messages；现在 Chat Completions 是第一类独立适配器，必须补充自己的消息、响应、流式和结构化输出模型。
2. **OpenAI 与 Anthropic 使用固定官方地址**：现在三类都允许填写中转站 endpoint；官方地址只能作为预填示例/默认值。
3. **“OpenAI Responses-compatible”是一种独立类型**：现在第二类正式是 OpenAI Responses API 协议适配器。“compatible”是某个配置经探测得到的有限证据，不是类型名。
4. **只有 Responses-compatible 需要处理自定义地址的不确定性**：现在三类 endpoint 都可能指向中转站，三类都必须按 endpoint + 模型探测，不能仅凭适配器名称推断兼容性。
5. **只在 API root 后追加 `/responses` 的全局规则**：该规则不能覆盖三类协议。若保留 root 模式，追加路径必须由适配器决定；若支持任意中转路由，应改为完整 endpoint 或显式的 root/full-endpoint 两种模式。
6. **OpenAI 生成默认值只有 Responses wire 形状**：Chat Completions 的 `reasoning_effort`、`max_completion_tokens`、`response_format` 与 Responses 的 `reasoning.effort`、`max_output_tokens`、`text.format` 必须分开建模。

### 仍然成立，但需改写适用范围

- 每种类型保留隔离配置、精确模型标识由用户纯文本填写、不自动获取模型列表。
- “字段未设置”与“显式发送默认值”必须区分。
- 服务生成默认值属于具体适配器，不进入虚假的跨协议公共 wire 接口。
- 流式和结构化输出是 endpoint + 模型级能力，支持/不支持/未知应来自探测。
- 校验基线应覆盖所有会改变实际请求的内容；现在还必须覆盖三种配置各自的完整 endpoint、协议适配器种类以及鉴权/版本头方案。

## 九、建议用于后续领域建模的名称

- `AI 服务类型` 可继续保留，但其三个值应明确是：`OpenAI Chat Completions`、`OpenAI Responses`、`Anthropic Messages`。
- 将“服务类型”解释为**请求/响应协议边界**，不要解释为供应商或官方/中转归属。
- 每个 `AI 服务配置` 持有自己的 `请求端点`、凭据引用、模型标识、协议专属默认值和校验证据。
- `请求端点` 表示最终接收创建请求的完整 URL；若产品最终坚持 root 模式，则领域词必须显式叫 `API root`，并由适配器解析成请求端点。二者不要混用。
- `AI 服务能力` 的证据主体应是配置，而不是协议类型；同一个中转站甚至同一个模型在 Chat Completions 与 Responses 上可能得出不同结论。

## 十、完整 HTTP(S) endpoint 的 userinfo、query 与 fragment

| URL 组件 | 标准请求语义 | 对请求端点契约的推论 |
| --- | --- | --- |
| `userinfo`，如 `user:pass@` | URI 通用语法允许用户名及可选的授权信息，但 `user:password` 形式已弃用。HTTP(S) 进一步规定发送方不得在作为 target URI 或字段值的 URI 中生成 userinfo；HTTP/1.1 的 `Host` 也明确排除 userinfo。 | 拒绝含用户名或密码的 endpoint。不要依赖 HTTP 库把它静默转成 Basic Auth。 |
| `query`，如 `?route=a` | query 与 path 一起标识目标资源；HTTP/1.1 的常见 origin-form request target 明确是 `absolute-path [ "?" query ]`，所以 query 会发送给服务器。 | 若允许 query，必须原样保留并纳入校验基线；若禁止，这是为了简化产品契约，而不是因为 HTTP 不支持。 |
| `fragment`，如 `#section` | fragment 在 URI 解引用前由客户端从其余 URI 分离，不参与协议处理；HTTP(S) URI 和 request target 只包含 path 与可选 query。fragment 不会发送给服务器。 | 拒绝 fragment，避免两个字符串不同的配置实际请求同一个 endpoint，并避免用户误以为中转站会收到它。 |

上述 userinfo 结论来自 [RFC 3986 §3.2.1](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.2.1) 与 [RFC 9110 §4.2.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2.4)：前者说明其通用 URI 语义及明文密码风险，后者对 HTTP(S) 明确弃用并建议把不可信 URI 中的 userinfo 视为错误。[RFC 9112 §3.2.1](https://www.rfc-editor.org/rfc/rfc9112.html#section-3.2.1) 还规定 `Host` 排除 userinfo。标准 Basic 鉴权通过独立的 `Authorization` header 表达，见 [RFC 7617 §2](https://www.rfc-editor.org/rfc/rfc7617.html#section-2)；某个客户端是否把 URL userinfo 转换成该 header 属于实现行为，不应成为适配器契约。

query 的资源标识语义见 [RFC 3986 §3.4](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.4)；其在 HTTP request target 中的传输形式见 [RFC 9112 §3.2.1](https://www.rfc-editor.org/rfc/rfc9112.html#section-3.2.1)。fragment 的客户端侧语义见 [RFC 3986 §3.5](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.5)，HTTP 对 fragment 的边界见 [RFC 9110 §4.2.5](https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2.5)。

## 官方来源索引

### OpenAI

- [Create chat completion](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- [Chat Completions streaming events](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)
- [Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [Responses streaming events](https://developers.openai.com/api/reference/resources/responses/streaming-events)
- [API Overview: authentication and REST version](https://developers.openai.com/api/reference/overview)

### Anthropic

- [Create a Message](https://platform.claude.com/docs/en/api/messages/create)
- [Streaming Messages](https://platform.claude.com/docs/en/build-with-claude/streaming)
- [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [Authentication](https://platform.claude.com/docs/en/manage-claude/authentication)
- [Versions](https://platform.claude.com/docs/en/api/versioning)
- [Stop reasons and fallback](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)

### URI/HTTP 标准

- [RFC 3986: URI Generic Syntax](https://www.rfc-editor.org/rfc/rfc3986.html)
- [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html)
- [RFC 9112: HTTP/1.1](https://www.rfc-editor.org/rfc/rfc9112.html)
- [RFC 7617: Basic HTTP Authentication](https://www.rfc-editor.org/rfc/rfc7617.html)
