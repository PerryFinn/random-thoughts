# Responses 校验与日报生成

本切片承接 [#29](https://github.com/PerryFinn/random-thoughts/issues/29) 与父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20)，基于本地 `b1b7320` 的 #28 实现。2026-10-15 只读核对远端 main 为 `123948d`，#29 仍被开放的 #28 阻塞，#28 仍被开放的 #24／#26／#27 阻塞。本地继续实现不改变这些远端状态。

## 原生协议

Responses 独立编码 `instructions`、`input`、`reasoning.effort`、`max_output_tokens`、`store:false`、`truncation:disabled`，使用原生 Bearer 鉴权；未设置的温度和思考强度不发送。结构化能力已证明支持时使用 `text.format` 的严格 JSON schema，否则只使用共享的固定可解析文本契约。不发送 Chat Completions 的 `messages`／`response_format`／`reasoning_effort` 或 Messages 字段。

非流式只解析 HTTP 实际 `output` 数组内已完成 assistant message 的 `output_text` 块，按原顺序拼接；不使用 SDK 聚合属性 `output_text`。reasoning 项不作为正文；拒绝、工具项、未知内容、错误、截断或非完成状态均不能成为日报。

SSE 增量解析 UTF-8、LF／CRLF／CR 和多行 data，核对事件类型、递增序号、响应／输出项／内容块身份与完成顺序。必须有有效文本、对应内容与输出项完成、以及相符的 `response.completed`；`[DONE]` 不替代 Responses 的合法终止。`response.failed`、`response.incomplete`、`error` 与 refusal 立即失败，未知事件不冒充有效进展。合法终止即结束请求，不等待连接关闭；心跳不延长 90 秒无进展期限。

请求使用完整端点并保留 query、路由和尾斜杠，不追加路径、拉取模型清单、跟随重定向、自动重试或删除必要控制字段重发。明文 HTTP 沿用配置界面的持续说明。错误只保留固定分类与可靠 Retry-After，禁止原始错误正文进入日志或提示。

原生 `unsupported_value` 与明确参数拒绝使用相同规则：必要字段或默认值不支持则校验失败；只有对应可选探测的 stream／text.format 拒绝才能记录能力不支持，正式请求仍失败且不降级重发。

## 共享流程与预算

保存、三个显式合成探测、设为当前、生成、编辑和保存共用 `DailyReportFlow.send`。探测使用实际模型、默认值、O 与必要控制，不带工作正文或生成偏好。基础成功才有资格；明确拒绝可选 stream／text.format 才是不支持，临时未完成保留整份旧结论。明确鉴权、模型或必要参数错误撤销匹配基线的资格，当前身份保留；不串用其他协议配置或凭据。

复用 #28 的固定事实指令、不可变快照、离线双编码、辅助 20% 上限、规范六章节、取消代次及草稿／来源原子更新。预算计算使用 Responses 实际序列化的 `text` schema 包装；不复制长输入规划。当天完整输入超出直接预算时停止且不外发，完整分批仍由 #31 承接。保存成功才清临时来源，失败、取消、旧回调不能替换原正文或来源；不新增持久化档案或数据迁移。

## 验证边界

沿用父规格已确认的统一流程动作／状态、真实 HTTP 本机假服务、SQLite／CryptoKit、tokenizer 与 CocoaLumberjack 边界。测试只使用合成内容、独立临时数据库和沙盒允许的唯一回环端口，验证原生 DTO、output、SSE、错误证据、配置隔离、预算及草稿保存闭环。

实际命令、结果和未执行项目记录于 [testing.md](testing.md)。纯构建及隔离通过不能宣称真实端点兼容；三协议真实组合人工结果由 #36 统一收集，真实语义／系统验收由授权后的 #35 承接。

协议依据：[Responses 创建接口](https://developers.openai.com/api/reference/resources/responses/methods/create)、[Responses 流式事件](https://developers.openai.com/api/reference/resources/responses/streaming-events)、[OpenAI 仓库中的 unsupported_value 原生错误示例](https://github.com/openai/codex/issues/2625)。
