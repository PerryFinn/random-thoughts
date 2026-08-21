# AI 服务专属生成默认值：协议事实与校验含义

> 调查日期：2026-08-20  
> 范围：OpenAI Responses API、Anthropic Messages API，以及对“OpenAI Responses-compatible”自定义端点能够诚实作出的最小判断。本文不替产品作决定；“官方事实”和“设计建议/推论”分开陈述。

## 结论摘要

1. 两家服务都没有一个跨模型稳定的“温度 + 思考强度”组合。请求 schema 给出的枚举是超集，实际支持和值的默认行为取决于模型。
2. OpenAI Responses 的 `temperature` 与 `top_p` 是可选采样字段，官方建议只调整其中一个；`reasoning.effort` 是另一个模型相关字段。以 GPT-5.2 为例，`temperature`/`top_p` 仅在 `reasoning.effort: "none"` 时受支持，而某些其他 GPT-5 模型会直接拒绝这些字段。
3. Anthropic 的当前思考模型主要使用 `thinking: {type: "adaptive"}` 与 `output_config.effort`；旧模型可能只支持 `thinking: {type: "enabled", budget_tokens: N}`。这两种协议形态不能压成一个无损的公共标量。
4. Anthropic 当前多种新模型会在任何请求中拒绝非默认 `temperature`、`top_p`、`top_k`，不论是否开启 thinking；因此“温度”只能作为模型相关、允许完全省略的旧式/条件式默认值。
5. 如果“测试配置成功”要证明随后使用默认值的真实生成可用，验证指纹必须覆盖所有会进入请求且可能导致 400 的服务专属控制项，并保留“字段省略”和“显式默认值”的区别。只探测 endpoint、密钥和模型不足以证明完整调用配置可用。
6. OpenAI 官方文档只定义 OpenAI 服务，不定义第三方 Responses-compatible 的一致性等级。对自定义端点，一次成功请求只能证明该端点接受了被测请求元组，不能证明它支持 OpenAI 的全部字段、枚举、模型规则，甚至不能证明已接受的字段产生相同语义。

## 一、OpenAI Responses API：官方事实

### 1. 请求字段

以下均来自官方 [Create a model response API Reference](https://developers.openai.com/api/reference/resources/responses/methods/create)：

| 控制项 | 精确 wire 位置 | 官方 schema / 语义 | 重要限制 |
| --- | --- | --- | --- |
| 采样温度 | `temperature` | 可选 number，范围 `0...2`；数值越高越随机 | 官方建议只调整 `temperature` 或 `top_p` 之一，而不是同时调整 |
| nucleus sampling | `top_p` | 可选 number；`0.1` 表示只考虑累计概率前 10% 的 token | 同样建议不要与 `temperature` 同时调整；当前 Responses Markdown reference 没有为该字段公布数值边界，不能仅凭此页制造更严格的本地范围 |
| 推理投入 | `reasoning.effort` | schema 超集为 `none | minimal | low | medium | high | xhigh | max` | 官方明确说明并非每个 reasoning model 都支持每个值 |
| 推理执行模式 | `reasoning.mode` | schema 包含 `standard | pro` | `pro` 是当前特定模型能力，不是任意 Responses 模型的通用能力 |
| 输出冗长度 | `text.verbosity` | `low | medium | high`，默认 `medium` | 属于模型能力；不是纯文本 Responses 的最低兼容承诺 |
| 输出上限 | `max_output_tokens` | 可选 number；限制“可见输出 token + reasoning token”的总数 | 具体模型有不同输出上限；过低时 reasoning 可能在可见文本前耗尽预算 |

`reasoning.effort` 的作用是引导模型投入多少推理；值和默认值都是模型相关的。官方 reasoning guide 明确列出 schema 可能出现的七个值，并说明更低 effort 偏向更低延迟/更少 token，更高 effort 偏向更完整的思考：[Reasoning effort](https://developers.openai.com/api/docs/guides/reasoning#reasoning-effort)。

`temperature` 与 `top_p` 并非一般意义上的强互斥字段：通用 API reference 的措辞是“建议只调整一个”。但是，具体 reasoning 模型会增加更严格的合法性规则。

### 2. 模型支持不是一个固定枚举

官方文档中的几个反例足以证明，不能把 Responses schema 超集直接当成每个模型的可选项：

| 模型/模型族 | 官方记录的 `reasoning.effort` | 其他相关约束 |
| --- | --- | --- |
| GPT-5.6 | `none | low | medium | high | xhigh | max`；省略时默认 `medium` | 支持 `reasoning.mode: "standard" | "pro"`，mode 与 effort 独立。见 [GPT-5.6 model guidance](https://developers.openai.com/api/docs/guides/latest-model) |
| GPT-5.4 | `none`（默认）、`low | medium | high | xhigh` | 见 [GPT-5.4 model page](https://developers.openai.com/api/docs/models/gpt-5.4) |
| GPT-5.4 Pro | `medium`（默认）、`high | xhigh` | 见 [GPT-5.4 Pro model page](https://developers.openai.com/api/docs/models/gpt-5.4-pro) |
| GPT-5 Pro | 只支持 `high`，且默认即为 `high` | 见 [GPT-5 Pro model page](https://developers.openai.com/api/docs/models/gpt-5-pro) |
| GPT-5.2 | `none`（默认）、`low | medium | high | xhigh` | `temperature`、`top_p`、`logprobs` 仅在 effort 为 `none` 时支持 |
| GPT-5 / GPT-5 mini / GPT-5 nano（旧代） | 各有自己的 effort 子集 | GPT-5.2 guidance 明确说这些旧 GPT-5 模型若带 `temperature`/`top_p` 会报错 |

GPT-5.2 的兼容规则尤其明确：`temperature`、`top_p`、`logprobs` 仅在 `reasoning.effort: "none"` 时支持；GPT-5.2 或 GPT-5.1 使用其他 effort，或旧 GPT-5 系列携带这些字段，会返回错误。官方给出的替代控制是 `reasoning.effort`、`text.verbosity` 和 `max_output_tokens`：[GPT-5.2 parameter compatibility](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.2#parameter-compatibility)。

这条 GPT-5.2 规则不能反向推导所有未来或第三方模型的行为。当前通用 Responses schema 只说明字段形状；模型页和真实请求才说明特定模型是否接受组合。

### 3. 模型查询不能替代控制项探测

OpenAI 的 `GET /v1/models/{model}` 返回模型 `id`、`created`、`object`、`owned_by` 等基本信息；官方 reference 没有返回 reasoning effort、temperature、verbosity 等逐项能力位：[Retrieve model](https://platform.openai.com/docs/api-reference/models/retrieve)。因此：

- 查询模型可以证明该凭据能看见某个模型，但不能证明某组生成控制项有效。
- 对一个手填模型标识，若要证明 `reasoning.effort`、`temperature`、`text.verbosity` 等组合可用，仍需要发送覆盖该组合的 Responses 请求。
- 通用 schema 或模型名字符串不能替代服务器端验证。

以上后两点是基于官方返回结构的推论，不是 OpenAI 对应用验证流程的产品规定。

## 二、Anthropic Messages API：官方事实

### 1. 请求字段

以下字段和形状来自官方 [Create a Message API Reference](https://platform.claude.com/docs/en/api/messages/create)：

| 控制项 | 精确 wire 位置 | 官方 schema / 语义 | 重要限制 |
| --- | --- | --- | --- |
| 输出上限 | `max_tokens` | 必填 number；是本次响应的硬输出上限，模型可提前停止 | 不同模型最大值不同；thinking token 与可见文本共同计入 |
| 采样温度 | `temperature` | 可选 number，`0...1`，默认 `1.0`；`0` 也不保证确定性 | 新模型通常拒绝非默认值；允许完全省略是必要状态 |
| nucleus sampling | `top_p` | 可选 number，`0...1`；高级用法 | 已弃用于新模型；模型兼容面比字段存在本身更窄 |
| thinking 模式 | `thinking.type` | `disabled | adaptive | enabled` 的 tagged union | 每个模型接受的分支不同，不能视为三个普遍可用选项 |
| 手动 thinking 预算 | `thinking.budget_tokens` | 只在 `type: "enabled"` 分支出现；通常至少 `1024` 且严格小于 `max_tokens` | 4.6 已弃用，4.7+ 拒绝；interleaved thinking 有预算例外 |
| thinking 展示 | `thinking.display` | `summarized | omitted` | 控制返回的摘要是否展示，不等同于关闭思考，也不减少 thinking 计费 |
| 整体投入 | `output_config.effort` | schema 超集 `low | medium | high | xhigh | max` | 支持模型和支持等级不同；`adaptive` 不是 effort 值 |

`max_tokens` 与 OpenAI 的同名概念不能直接共用 wire 模型：Anthropic 字段是 Messages 请求必填项；OpenAI Responses 使用可选 `max_output_tokens`。Anthropic 还允许 `max_tokens: 0` 做 prompt-cache 预热，但这不是生成日报的正常输出配置；见 [Create a Message](https://platform.claude.com/docs/en/api/messages/create#body-params)。

### 2. thinking 有两套仍在使用的协议形态

Anthropic 官方兼容矩阵见 [Thinking troubleshooting — supported models](https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting#supported-models)。关键区别是：

- 当前 adaptive 路径：`thinking: {"type": "adaptive"}`，由 `output_config.effort` 控制整体投入，并在 adaptive 模式中影响 thinking 的频率和深度。
- 旧式 manual 路径：`thinking: {"type": "enabled", "budget_tokens": N}`，直接给出 thinking token 目标预算。
- Claude 4.6 仍接受 manual，但已弃用；4.7 及更新模型拒绝 `type: "enabled"` 并返回 400。
- Claude 4.5 及更早的 thinking 模型只支持 manual，使用 `type: "adaptive"` 会返回 400。
- 一些最新模型默认开启或始终开启 thinking；`disabled` 也不是普遍合法。例如 Claude Opus 5 在 `xhigh`/`max` effort 下不能与 `thinking.type: "disabled"` 组合。

因此，Anthropic 服务内也不能用一个 `thinkingEnabled: Bool` 或一个公共“思考强度”完整表达协议。官方 [Effort guide](https://platform.claude.com/docs/en/build-with-claude/effort) 明确区分：`thinking` 决定是否/以何种模式思考，`output_config.effort` 控制整份响应的投入，包括文本、工具调用和已启用的 thinking；effort 是行为信号，不是严格 token 预算。

### 3. sampling 与 thinking 的兼容性随代际变化

Anthropic 当前官方 [Thinking — limits and feature compatibility](https://platform.claude.com/docs/en/build-with-claude/thinking#limits-and-feature-compatibility) 给出的规则是：

- Claude Fable 5、Mythos 5、Mythos Preview、Opus 5、Opus 4.8、Opus 4.7、Sonnet 5 对任何请求中的非默认 `temperature`、`top_p`、`top_k` 返回 400，不论是否开启 thinking。
- 较旧模型只有在 thinking 开启时受更严格约束：`temperature` 与 `top_k` 不兼容，`top_p` 只允许 `0.95...1`。
- API primer 将共同规则概括为：thinking 开启时，`temperature` 必须为 `1` 或省略；Claude 4.7 及以后模型即使关闭 thinking，也只接受默认 temperature。见 [API usage primer — Thinking](https://platform.claude.com/docs/en/claude_api_primer#thinking)。
- Messages API reference 进一步将 `top_p` 标为 deprecated：Opus 4.6 之后的模型不支持设置它，仅为向后兼容接受 `>= 0.99` 的值。见 [Create a Message — top_p](https://platform.claude.com/docs/en/api/messages/create#body-params)。

这说明 `temperature`/`top_p` 在 Anthropic 中应被视为“可省略、按模型验证”的候选默认值，而不是总会序列化的服务级公共字段。官方资料没有把当前 Anthropic sampling 与 effort 定义成可以同时自由组合的矩形能力空间。

### 4. Anthropic 提供逐模型能力查询，但仍不是完整 dry-run

Anthropic 官方提供 `GET /v1/models/{model_id}`。它可按用户给出的 ID/alias 检索单个模型，并返回：

- 规范模型 `id`；
- `max_tokens`；
- `capabilities.thinking.supported`；
- `capabilities.thinking.types.adaptive/enabled.supported`；
- `capabilities.effort` 以及 `low/medium/high/xhigh/max` 的逐级支持位。

见 [Get a Model](https://platform.claude.com/docs/en/api/models/retrieve)。这是一项精确模型查询，不要求先获取模型列表。

它仍不能完整替代生成探测：模型能力响应没有 temperature/top_p 的支持位，也不能证明某个 thinking、effort、sampling、max_tokens 组合在当前凭据下共同有效。

Anthropic 另有 `POST /v1/messages/count_tokens`，可在不创建生成结果时解析模型、messages、thinking 和部分 `output_config`；但其官方请求结构不含生成用的 `temperature` 与 `max_tokens`，所以不是完整生成配置的 dry-run：[Count tokens in a Message](https://platform.claude.com/docs/en/api/messages/count_tokens)。要验证最终组合，仍需实际 `POST /v1/messages`。最后一句是对官方接口范围的推论。

### 5. 错误类别有不同的配置含义

Anthropic 官方将常见错误区分为 `400 invalid_request_error`、`401 authentication_error`、`402 billing_error`、`403 permission_error`、`404 not_found_error`、`429 rate_limit_error`、5xx 和 `529 overloaded_error`：[Claude API errors](https://platform.claude.com/docs/en/api/errors)。

- 400 更可能证明请求字段/模型组合不合法。
- 401/403 可证明凭据或权限问题，但不是生成控制 schema 本身的问题。
- 429、5xx、529 是限流或暂时性故障，不能诚实地永久标记配置为“不支持该能力”。

后两条是对官方错误语义的验证状态建模建议。

## 三、Responses-compatible 自定义端点的证据边界

### 官方事实

本次查阅的 OpenAI API reference 描述 `api.openai.com/v1/responses` 的请求和 OpenAI 模型行为。它没有定义第三方实现必须通过的 conformance profile，也没有承诺相同 JSON 字段在其他服务上具有相同语义。

### 设计建议/推论

因此，对用户提供的 Responses-compatible API root，以下内容不能仅凭“compatible”标签诚实宣称为已支持：

- OpenAI `reasoning.effort` 的完整枚举或任一模型的默认值；
- `reasoning.mode: "pro"`；
- `text.verbosity`；
- GPT-5.2 的 sampling/reasoning 组合规则；
- 通过模型 ID 前缀推断模型能力；
- OpenAI 官方模型页列出的输出上限或能力；
- “请求未报错”即表示某个控制项被实现并产生了 OpenAI 相同语义。

`temperature`、`top_p`、`max_output_tokens`、`reasoning` 等字段可以作为该适配器自己的 endpoint-scoped 候选设置，但只能在端点文档明确声明或实际探测成功后记录为“该请求组合被接受”。尤其要保留三种不同结论：

1. 未发送该字段，能力未知；
2. 发送后请求被接受；
3. 字段确实改变了模型行为。

一次普通探测通常只能证明第 2 点，无法低成本证明第 3 点。

## 四、哪些控制项适合作为“少量服务专属默认值”的候选

下表是候选集与证据条件，不是产品决策：

| 服务 | 候选 | 能够诚实保存/发送的前提 | 不应被掩盖的状态 |
| --- | --- | --- | --- |
| OpenAI | `temperature` | 目标模型与所选 effort 的实际组合通过验证 | 省略 vs 显式数值 |
| OpenAI | `top_p` | 与 `temperature` 二选一，并通过目标模型验证 | 省略 vs 显式数值 |
| OpenAI | `reasoning.effort` | 目标模型支持所选枚举值 | 省略（使用模型默认）vs 显式 effort |
| OpenAI | `text.verbosity` | 目标模型确认支持 | 省略 vs `low/medium/high` |
| OpenAI | `max_output_tokens` | 不超过目标模型限制，且给 reasoning 与可见文本留足空间 | 省略 vs 显式上限 |
| OpenAI | `reasoning.mode` | 只在确认支持的模型上（当前官方重点是 GPT-5.6） | `standard/pro` 不能泛化到其他模型或兼容端点 |
| Anthropic | `max_tokens` | 每个 Messages 生成请求都需要；不超过目标模型上限 | 与 thinking 共用硬预算 |
| Anthropic | thinking 模式 | 使用 tagged union：省略/default、`disabled`、`adaptive`、`manual(enabled)` | 模型可能拒绝某些分支，不能只存 Bool |
| Anthropic | `output_config.effort` | Model API 或完整请求确认模型和等级受支持 | 省略（官方默认通常为 high）vs 显式值 |
| Anthropic | manual `budget_tokens` | 仅属于 `enabled` 分支，满足预算约束，且模型仍支持 | 不能放进 adaptive 分支 |
| Anthropic | `temperature` | 仅对仍支持非默认 sampling 的模型；thinking 兼容规则通过验证 | 新模型上通常应完全省略 |
| Anthropic | `top_p` | 若保留，应定位为旧模型高级项并单独验证 | 已弃用；不能作为新模型常规控制 |

`thinking.display` 更接近应用的响应呈现/传输策略，而不是生成质量偏好；如果它确实进入请求，也会影响返回形态与首个可见文本时机，所以仍需纳入被测请求证据。是否暴露给用户由产品契约决定。

## 五、验证指纹与探测：基于事实的建议

### 1. 分开“连接可达”和“调用配置可用”

建议不要让一个布尔 `validated` 同时代表两种强度不同的证据：

- **连接证据**：API root、凭据、基本协议路径可用。
- **调用配置证据**：特定模型 + 特定服务专属控制组合能够完成目标生成请求。

Anthropic 的精确 Model API 可以提供中间层“模型存在且声明这些能力”；OpenAI 的 Model API 不提供逐控制项能力，因此更依赖实际 Responses 探测。

### 2. 若成功状态承诺真实生成可用，指纹应覆盖

- 服务类型与规范化 API root；
- 协议版本/固定 header（例如 `anthropic-version`）和适配器请求 schema 版本；
- 凭据引用的稳定 ID 与轮换版本/摘要，不能保存明文密钥；
- 用户输入的模型标识；若服务返回 alias 对应的规范模型 ID，也保存为验证证据；
- `temperature` 的“缺席/存在”及数值；
- `top_p` 的“缺席/存在”及数值；
- OpenAI 的 `reasoning.effort`、`reasoning.mode`、`text.verbosity`、`max_output_tokens`（只要默认生成会发送）；
- Anthropic 的 `max_tokens`、thinking tagged-union 分支、manual `budget_tokens`、`output_config.effort`、`thinking.display`（只要默认生成会发送）；
- 任何其他真实进入日报生成请求、并可能使服务返回 400 的服务专属默认值。

理由：上述任一变化都可能把先前成功的请求变成无效组合。指纹还必须区分“省略字段”和“显式发送供应商默认值”，因为 Anthropic 新模型的兼容规则尤其依赖是否发送 sampling 字段。

### 3. 建议的分层探测

1. **本地 schema 校验**：数字范围、tagged union、显然的互斥与跨字段约束，例如 Anthropic manual `budget_tokens >= 1024` 且通常 `< max_tokens`。
2. **精确模型元数据**：Anthropic 可调用 `GET /v1/models/{model}` 获取规范 ID 与 thinking/effort 能力；OpenAI 的对应接口只能证明模型可见，不能证明控制项能力。
3. **完整生成探测**：发送未来真实生成会采用的控制组合，而不是删掉所有高级字段的“最小成功请求”。否则成功结果不能为这些默认值背书。
4. **保存验证证据**：输入指纹、规范模型 ID（若有）、能力快照（若有）、验证时间、请求 ID、成功到达的阶段，以及暂时性失败/永久性不合法的分类。

探测本身还应避免两个假阴性：OpenAI 的 `max_output_tokens` 同时覆盖 reasoning 与可见文本；Anthropic 的 `max_tokens` 也同时覆盖 thinking 与文本。给探测设置过小预算，可能得到 `incomplete`/`max_tokens` 截断，而不是证明配置或模型无效。

### 4. 探测成功能证明什么

最稳妥的证据表述是：

> 在时间 T，凭据 C、端点 E、模型字符串 M（规范模型 ID 为 N，如服务提供）、控制项集合 P 的一次目标协议请求被服务接受，并产生了符合最低响应契约的结果。

它不证明：未来模型 alias 不会漂移、第三方 compatible endpoint 实现了所有 OpenAI 语义、未发送的可选能力受支持，或 sampling 参数会产生可测量的行为变化。

## 六、对后续领域建模最重要的约束

- “服务配置默认值”应是按服务类型分支的 tagged data，而不是一个跨服务参数字典，也不是伪公共 `temperature/thinkingStrength` 接口。
- 即使在同一服务类型内，模型仍决定哪些分支和值合法；配置层需要表达 `unset`、显式值、未知能力、已探测支持、探测失败。
- Anthropic 的 thinking 至少有 `adaptive + effort` 与 `manual + budget_tokens` 两种协议形态；OpenAI 的 reasoning effort、verbosity、sampling 则是相互有关但不同的控制轴。
- 验证结果应绑定“实际请求配置”，而不只绑定连接信息。若产品只想测试连通性，应使用不同状态名，避免把较弱证据误称为“可以按当前默认值生成”。
