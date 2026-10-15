# Messages 校验与日报生成

本切片承接 [#30](https://github.com/PerryFinn/random-thoughts/issues/30) 与父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20)，基于本地 `06da0cf`。2026-10-15 只读核对远端 main 为 `123948d`，#30 仍被开放的 #28 阻塞，#28 仍被开放的 #24／#26／#27 阻塞。前置代码已在本地，不改变远端阻塞或发布状态。

## 原生协议

Messages 独立编码 `system`、用户 `messages`、`max_tokens`，使用 `x-api-key` 和固定 `anthropic-version:2023-06-01`。温度范围 0–1，未设置不发送；thinking 端点默认不发送，关闭发送 `disabled`，adaptive 发送 `adaptive`，仅 adaptive 可带已设置的 `output_config.effort`。不增加手动 thinking budget，不发送 Bearer、store、truncation、reasoning 或其他协议的输出控制。

已证明结构化能力时用 `output_config.format` 的 `json_schema`／schema；它与 effort 同属原生 output_config。其他情况下使用统一的固定文本契约。事实提取、事实归并和成文共用业务意图，均由本适配器编码，不复制预算或分批调度。

非流式按内容块顺序仅拼接 text，thinking／redacted_thinking 不进入正文。须为 assistant message、存在非空文本并正常 end_turn；拒绝、截断、工具调用、暂停、未知内容或未完成均失败，不能把可解析的部分正文当作成功。原生 stop_details 拒绝信息同样阻止入草稿。

SSE 复用纯分帧器，独立验证 message_start、逐块 start／delta／stop、message_delta 和 message_stop；块索引、类型与顺序须一致，完整文本及正常结束缺一不可。thinking／signature 增量只用于协议进展，不作为正文；ping、注释或未知事件不延长无有效进展期限。error、拒绝、截断及非法终止失败；`[DONE]` 不能替代 message_stop。合法结束立即完成，不等待连接关闭。

完整端点、query 和尾斜杠原样使用，不追加路径、不跟随重定向、不自动重试。错误只外露固定分类和可靠 Retry-After；明确拒绝对应可选字段才记能力不支持，必要字段拒绝及正式请求的可选字段拒绝均失败，不删除字段重发。

原生 invalid_request_error 也可能表示消费限制，不能仅凭类型撤销资格。只接受明确结构化参数证据及有限的原生字段拒绝句式，包括模型明确拒绝 disabled thinking 的已知提示；此时撤销对应基线资格，不按提示改用其他模式。无参数、无明确字段证据的错误保留未知。permission_error／not_found_error 不直接证明 Key 无效或模型不存在，billing_error 只说明服务限制，不推断余额不足。原始错误句子仅在内存中判别，不进入提示或日志。

## 共享流程与隐私

保存、基础／流式／结构化三个显式合成探测、设为当前、生成、编辑和保存统一走 `DailyReportFlow.send`。探测最多三次，只含合成输入并采用真实模型、原生默认值、O 和凭据，不含工作正文或偏好；校验不自动设为当前。基线绑定固定版本头、真实请求字段、逻辑 Key 版本、O 与探测契约；临时未完成保留完整旧结论，明确配置错误仅撤销匹配基线资格，保留当前身份。

复用不可变快照、离线 tokenizer、辅助 20% 上限、固定六章节、取消代次与草稿／实际来源原子更新。schema 按实际原生包装计数。直接预算不足时停止且不外发，完整分批由 #31 承接。失败、取消、陈旧回调和保存失败保留旧正文／来源；保存成功才清关联。敏感对象不进日志，不增加数据库结构、迁移、生成档案或请求缓存。

## 验证边界

使用父规格已确认的统一流程动作／状态、协议 wire、本机 HTTP 假服务、真实 SQLite／CryptoKit／tokenizer／CocoaLumberjack。仅合成材料、独立临时目录和沙盒允许的唯一回环端口；连接 30 秒、非流式 300 秒、流式无有效进展 90 秒，取消及旧回调使用受控屏障验证。

实际命令、结果与未执行项目记录于 [testing.md](testing.md)。隔离假服务不能证明真实端点兼容；真实组合人工证据由 #36 承接，真实语义／系统验收由授权后的 #35 承接。

协议依据：[Messages 创建接口](https://platform.claude.com/docs/en/api/messages/create)、[流式 Messages](https://platform.claude.com/docs/en/build-with-claude/streaming)、[结构化输出](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)、[错误类型](https://platform.claude.com/docs/en/api/errors)。
