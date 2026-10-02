# 日报长上下文预算：协议事实与规划边界

> 调查日期：2026-09-19
>
> 状态：研究资料，不是独立决议。最终产品规则见[确定长上下文预算、分批汇总与质量降级策略](https://github.com/PerryFinn/random-thoughts/issues/16)；本文不实现生产功能。
>
> 方法：阅读 OpenAI Docs 与 Anthropic 官方资料；没有调用生成或计数 API，没有读取凭据。

## 对决策最有影响的事实

1. 三类协议的输出上限均不能解释为“可见日报字数”：推理或思考也占输出额度。
2. 官方服务有服务端输入计数能力，但不能从任意完整中转 endpoint 推导该能力或地址；本地估算也不是任意模型的容量保证。
3. 截断是独立的失败信号；一段能解析的 JSON 不代表完整生成成功。
4. 应用预算、模型上下文容量、可见中间摘要长度和整次请求规模是不同概念。任何默认数值、自动执行门槛及是否设置整次上限都是产品选择，不能冠以协议保证。

## 输出额度与完成信号

| 协议 | 请求输出上限 | 额度含义 | 需拒绝作为完整结果的信号 |
| --- | --- | --- | --- |
| Chat Completions | `max_completion_tokens` | 包括可见输出与推理 token；旧 `max_tokens` 已弃用，且并非所有模型兼容 | `choices[].finish_reason = length`；过滤、拒绝等另按失败分类 |
| Responses | `max_output_tokens` | 包括可见输出与推理 token | `status = incomplete`，尤其 `incomplete_details.reason = max_output_tokens` |
| Anthropic Messages | 必填 `max_tokens` | 本轮生成上限，思考 token 也包含在内 | `stop_reason = max_tokens` 或 `model_context_window_exceeded` |

字段及 Chat 完成原因来自 [Chat Completions 创建参考](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)；Responses 上限与未完成语义见 [Reasoning guide](https://developers.openai.com/api/docs/guides/reasoning)。Anthropic 请求字段见 [Messages 创建参考](https://platform.claude.com/docs/en/api/messages/create)，终止原因见 [Stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)。这些定义针对官方服务。

OpenAI 还说明输出用量可能包含不可见格式 token，不能用“总输出减推理”精确推导可见文本长度。即使推理计数为零，差额也未必为零。见 [Counting tokens](https://developers.openai.com/api/docs/guides/token-counting)。因此，中间摘要的可见文本大小约束应独立检查，不能直接以 wire 输出额度代替。

Anthropic 手动思考模式的 `thinking.budget_tokens` 在普通无工具请求中必须小于 `max_tokens`；支持该模式的模型也有限制。应用若自行降低输出额度，可能令用户原本合法的思考配置失效。不能静默修改用户思考模式来规避。见 [Extended thinking：Budget rules](https://platform.claude.com/docs/en/build-with-claude/extended-thinking#budget-rules-and-tuning)。

## 上下文核算与计数能力

对本功能的独立、无工具纯文本请求，规划需覆盖系统指令、模板/schema、来源标识、工作正文、辅助背景及消息封装，并为本轮全部输出预留空间。推理/思考包含在预留输出内，不应重复相加。OpenAI 推理 token 占上下文且可能在出现可见答案前耗尽额度；Anthropic 也把本轮思考与输出计入上下文。见 [OpenAI 上下文管理](https://developers.openai.com/api/docs/guides/reasoning#managing-the-context-window) 与 [Anthropic Context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows)。

| 计数方式 | 官方能力 | 本项目的适用边界 |
| --- | --- | --- |
| OpenAI Responses `POST /v1/responses/input_tokens` | 接受 Responses 输入形状，文档称返回模型实际接收的精确输入计数，包含消息角色和边界格式开销 | 不等于 Chat Completions wire 请求的计数契约；中转站不一定实现该路由 |
| Anthropic `POST /v1/messages/count_tokens` | 可计入 system、messages、tools 等；官方明确称估算，实际生成输入计数可能略有差异 | 必须对应实际模型和输入；不是绝对无误差证明 |
| 本地 tokenizer 或文本启发式 | OpenAI 文档承认本地 tokenizer 可处理纯文本，但请求结构、工具/schema 等会带来额外开销 | 任意模型别名不能可靠映射 tokenizer；字符除以固定常数不是通用精确计数 |

来源：[OpenAI Counting tokens](https://developers.openai.com/api/docs/guides/token-counting)、[Anthropic Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting)。计数本身也是发送内容的网络请求，不能因为它不生成文本就绕开内容发送范围和用户确认边界。

**设计推论：** 首版可以使用有版本号的本地保守估算，并明确这是“应用规划预算”。安全余量降低超限概率，但不构成对未知 tokenizer、中转隐藏提示或中转截断行为的证明。若以后接入远程计数，应单独定义 endpoint 配置、能力证据及失败规则；本票无需因此扩展服务发现功能。

## 禁止服务端自动丢输入

Responses 的 `truncation` 文档规定：`auto` 可丢弃对话开头的项以适配窗口；`disabled` 是默认值，超限时失败。为表达明确意图，可在实际请求中显式发送 `truncation: "disabled"`，并纳入实际调用配置校验。见 [Responses 创建参考：truncation](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)。

本次检查的 [Chat Completions 创建 schema](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create) 与 [Messages 创建 schema](https://platform.claude.com/docs/en/api/messages/create) 未提供与 Responses 同名的通用 `truncation` 开关；不能向它们盲目复制字段。Anthropic 对“输入加请求最大输出超过窗口”的处理还依模型行为而异：部分模型可接受请求，然后在窗口耗尽时返回 `model_context_window_exceeded`，其他情况可能验证失败。因此，“服务接受请求”不能证明所有预留输出都能生成。见 [Context windows：Context window validation](https://platform.claude.com/docs/en/build-with-claude/context-windows)。

**设计推论：** 应用保证自身不静默删除当天合规输入；不要启用自动压缩、自动上下文编辑或 SDK 隐式重试来扩展处理范围。对第三方中转，只能保证发送了哪些输入和字段，不能仅凭一次成功响应证明中转从未隐藏裁剪。该边界与既有 [中转协议研究](relay-ai-protocol-boundary.md) 一致。

## 产品概念的区分（正式取舍见决议）

- **请求规划预算**：应用容许某次请求携带的估算输入与预留输出，保存在对应 AI 服务配置；不是自动发现的模型上下文容量。
- **协议输出上限**：真实发送的协议专属字段；直接生成、分批提取和汇总都必须有确定且兼容的有效值，不能把“由服务默认”当作已受应用约束。
- **中间摘要大小约束**：约束供下一层使用的可见内容与来源信息；单批可发送不意味着全部摘要能装入最终请求。
- **整次生成计划**：在第一笔生成请求前，依据中间摘要大小约束及最终输出预留核对汇总是否可行，并估算请求规模。是否设置累计次数或层数上限是独立产品决策；没有固定上限也需要明确汇总收敛条件，不能无限重复压缩或丢批次。
- **完成与质量**：所有计划输入完成处理、所有必要批次成功且最终机械结构验收通过，是接受结果的必要条件；事实硬规则仍须满足，但既定首版运行时不具备自动证明语义正确的能力。截断、缺批次、预算耗尽不是“质量较低但成功”。这些是延续既定产品底线的建议，不是 API 自动提供的保障。

本文没有决定具体默认 token 数、估算公式、每批摘要长度、自动分批门槛或最大层数；它们须由 #16 的最终决议统一确定。
