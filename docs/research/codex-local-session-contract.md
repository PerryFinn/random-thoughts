# Codex 本机会话读取契约

研究日期：2026-08-14  
上游源码快照：[`openai/codex@6691980`](https://github.com/openai/codex/commit/66919805ea080053d1933b6b43afeb0d8bf70c91)（2026-08-13）  
本机验证版本：`codex-cli 0.146.0`

## 结论

首版应把 **Codex App Server 的 stdio JSON-RPC 接口**作为唯一受支持的会话解码契约：

1. 按用户设置向子进程传入 `CODEX_HOME`；未设置时让 Codex 使用 `~/.codex`。
2. 启动用户已安装的 `codex app-server`，完成 `initialize` / `initialized` 握手。
3. 分别调用 `thread/list`（`archived: false`）和 `thread/list`（`archived: true`），分页取得当前与归档线程。
4. 对用户选中的候选线程调用 `thread/read`（`includeTurns: true`），从规范化后的 `Thread -> Turn -> ThreadItem` 读取正文和元数据。
5. 只调用列表和读取接口；不得为了读取日报而 `thread/resume`、直接改写 JSONL、读取 `auth.json`，或依赖 `Thread.path`。

官方将 App Server 定位为需要“认证、会话历史、审批和流式事件”的深度产品集成接口；默认 stdio 传输是 JSONL，而 WebSocket 明确是实验性、非生产接口。[官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)；[协议源码](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server/README.md#L20-L37)

这意味着首版**不内置 rollout JSONL 字段解析器作为备用路径**。若找不到可用的 `codex`、握手失败、方法不存在或线程无法读取，应显示可行动的兼容性错误（安装或更新 Codex、检查目录权限），而不是静默猜测私有文件格式。

## 证据等级

本文使用以下三种等级，不能相互替代：

- **稳定公开契约**：Codex 官方文档公开描述的路径、环境变量或 App Server 方法/响应。
- **当前实现事实**：固定到上述 Git commit 的 OpenAI 官方源码；可帮助解释兼容性，但未来可能改变。
- **不可依赖推断**：从文件名、mtime、消息文本或本机样本猜测业务语义。

## 首版可依赖的公开契约

### Codex Home 与会话范围

`CODEX_HOME` 是 CLI、IDE 扩展和 App Server 共同使用的状态根目录，公开默认值是 `~/.codex`；自定义目录必须已存在。[官方环境变量文档](https://learn.chatgpt.com/docs/config-file/environment-variables#core-locations)

官方故障排查文档公开列出：

- 当前会话：`$CODEX_HOME/sessions`
- 归档会话：`$CODEX_HOME/archived_sessions`

两者默认位于 `~/.codex` 下。[官方故障排查文档](https://learn.chatgpt.com/docs/troubleshooting#logs-and-diagnostics)

公开契约只覆盖本机状态；尚未同步到该 `CODEX_HOME` 的云端聊天不在首版读取范围内。

### App Server 读取序列

使用默认 stdio transport，不启用实验能力：

```text
spawn codex app-server with selected CODEX_HOME
  -> initialize
  -> initialized
  -> thread/list { archived: false, ...pagination }
  -> thread/list { archived: true,  ...pagination }
  -> thread/read { threadId, includeTurns: true }
  -> close stdin / terminate child on app exit
```

`thread/list` 和 `thread/read` 都在公开 API 总览中；`thread/read(includeTurns: true)` 返回规范化的 turn 与 item 历史。`thread/turns/list` 和 `thread/items/list` 当前仍标为实验能力，首版不要依赖它们。[官方 App Server 文档](https://learn.chatgpt.com/docs/app-server#api-overview)；[当前请求类型](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1484-L1499)

App Server 可针对运行中的 Codex 会话执行只读请求；当前实现还把分页历史读取明确设计为并发读取 append-only rollout。读取路径不得使用 `thread/resume`，因为 resume 会把线程载入并可能取得写入所有权。[当前并发协议实现](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/src/protocol/common.rs#L693-L710)

`thread/list` 默认只列交互式来源，并支持独立的 `archived`、`cwd`、`sourceKinds`、排序和游标参数。`recencyAt` 在 turn 开始时推进，而 `updatedAt` 还会被后台输出等持久化变化推进。[官方 thread/list 说明](https://learn.chatgpt.com/docs/app-server#example-list-threads-with-pagination--filters)；[当前参数类型](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1207-L1266)

### 领域字段映射

| 日报领域字段 | 读取来源 | 首版语义 |
| --- | --- | --- |
| 会话身份 | `Thread.id` | 唯一去重键；不要从文件名解析 |
| 当前/归档 | 发起 list 时的 `archived` 参数 | 同一 id 只保留一次；归档状态来自查询集合 |
| 显示标题 | `Thread.name ?? Thread.preview` | `name` 优先；均为空时生成本地占位标题 |
| 工作区分组 | `Thread.cwd` | 仅用于本地分组与展示；不要默认发送完整路径给 AI |
| 会话来源 | `Thread.source`、`Thread.parentThreadId`、`Thread.threadSource` | 排除子代理和自动化，不从标题推断 |
| 创建/最近活动 | `createdAt`、`recencyAt` | 候选发现用；不要把 `updatedAt` 等同于用户活动 |
| 日内活动 | `Turn.startedAt` | 报告日归属的规范粒度 |
| 用户内容 | `ThreadItem.type == userMessage` 的 `content` | 文本、图片、音频、skill/mention 是不同输入类型；首版需明确只送哪些类型给 AI |
| 助手内容 | `ThreadItem.type == agentMessage` | 日报上下文；不要把 reasoning、命令输出或工具输出默认为聊天正文 |
| Git 元数据 | `Thread.gitInfo` | 可选辅助标签，不是身份键 |
| 生产版本 | `Thread.cliVersion` | 仅诊断；不要用字符串比较代替能力探测 |

当前公开生成类型显示 `Thread` 包含 `id`、`parentThreadId`、`cwd`、`source`、`threadSource`、`name`、`createdAt`、`updatedAt`、`recencyAt` 与 turns；`Thread.path` 明确标为 **UNSTABLE**，因此不得进入业务模型。[当前 `Thread` schema](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts#L12-L84)

`Turn.startedAt` / `completedAt` 是可空 Unix 秒时间；`ThreadItem` 将用户消息和助手消息规范化成 `userMessage` / `agentMessage`。[当前 `Turn` schema](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts#L9-L37)；[当前 `ThreadItem` schema](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts#L30-L50)

### 报告日与时区契约

稳定 API 的最细可靠时间粒度是 **turn**，不是每条 user message：

1. 把用户选择的 IANA 时区（默认 Mac 当前时区）中的报告日转换为半开 UTC 区间 `[dayStart, nextDayStart)`；不要硬编码 24 小时，避免 DST 错误。
2. `Turn.startedAt` 落入区间且该 turn 至少含一个 `userMessage`，才构成“当天有用户活动”。
3. 该 turn 内由 `turn/steer` 追加的多个 user message 都继承 turn 的报告日；公开 `ThreadItem` 没有每条消息的时间字段。
4. 一次 turn 跨午夜时，整个 turn 按 `startedAt` 所在日期归属。若产品要求逐消息跨午夜切分，需要另开决策，当前稳定 API 无法满足。
5. `startedAt == null` 时不得用文件 mtime 或正文顺序伪造精确时间。把线程标记为“旧记录：日期精度不足”，允许用户手动纳入；只有首个/末个活动可谨慎显示 `createdAt` / `recencyAt` 提示。

当目标是“今天”时，可按 `recencyAt` 倒序分页并在早于 day start 后停止；指定历史日期时不能只看 `recencyAt`，因为它只表示最后一次 turn 开始，必须分页枚举线程后读取 turns。

### 子代理、自动化与噪声过滤

首版默认规则：

1. `thread/list` 不传 `sourceKinds`（采用官方的交互式默认集合）。
2. 二次过滤 `parentThreadId != null` 或 `source` 为 `subAgent` 的线程。
3. 二次过滤 `threadSource` 为已知自动化/内部类别（至少 `automation`、`subagent`、`memory_consolidation`）。
4. 未知 `source` / `threadSource` 不映射成用户线程；记录结构化兼容性诊断，并允许用户在“被过滤”分组中手动纳入。

当前源码的 `SessionSource` 明确区分 CLI、VSCode、Exec、MCP、自定义、内部与多种 SubAgent；thread-spawn 子代理还携带父线程 id 和深度。`ThreadSource` 允许任意 feature 字符串，因此不能假定自动化标识是一个封闭 enum。[当前来源类型](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/protocol/src/protocol.rs#L2566-L2662)

不要通过标题包含 “automation”、昵称、工作目录或消息文本推断代理关系。

### 标题与工作区

只消费 App Server 返回的 `name` 和 `preview`。当前实现把显式线程名另存为 `$CODEX_HOME/session_index.jsonl`，采取 append-only、同 id 最新记录胜出，但这是实现细节，不是公开存储契约。[当前 session index 实现](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/session_index.rs#L21-L70)

工作区首版只依赖 `Thread.cwd`。把 worktree 合并为同一“项目”、解析 Git remote、隐藏用户目录前缀等属于上层分组策略，不应混入会话存储适配器。

## 当前 rollout 实现事实（仅作兼容性证据）

以下事实固定到 `openai/codex@6691980`，**不得升级为产品契约**：

- 常量仍是 `sessions` 与 `archived_sessions`；活动 rollout 当前通常按 `sessions/YYYY/MM/DD/rollout-<timestamp>-<thread-id>.jsonl` 放置。[当前常量与目录遍历](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/lib.rs#L67-L75)；[当前布局注释](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/list.rs#L422-L425)
- 每行当前是 `{ timestamp, ordinal?, type, payload, metadata? }` 一类扁平 JSONL 记录；item 类型包括 session meta、response item、inter-agent communication、compaction、turn context、world state、security risk 和 event message。[当前 `RolloutLine`](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/history/src/lib.rs#L92-L104)；[当前 wire tag](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/history/src/rollout_payload.rs#L18-L51)
- `session_meta` 当前含 thread/session id、创建时间、cwd、source、thread source、父/派生关系、CLI 版本和可选 Git 信息；源码已经包含“旧记录没有 session_id 时回填 id”的兼容分支。[当前 `SessionMeta`](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/protocol/src/protocol.rs#L2855-L2918)；[旧格式兼容](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/protocol/src/protocol.rs#L2951-L2984)
- 用户消息至少存在 legacy `UserMessage` 与 paginated `ItemCompleted(UserMessage)` 两种持久化形态；规范化层主动兼容两者。[当前兼容代码](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/list.rs#L1179-L1195)
- revert 可让一个稳定 thread id 对应带另一 rollout id 后缀的新文件；文件名不是唯一身份契约。[当前文件名规则](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/rollout_file_name.rs#L39-L73)
- 当前读取器支持 `.jsonl.zst` 压缩 sibling，即使某台机器当前没有压缩文件，也不能假定永远只有纯 JSONL。[当前压缩选择逻辑](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/compression.rs#L995-L1025)
- writer 以 append 方式打开文件，对每条序列化记录追加换行并 flush。直接并发读取仍可能在某一瞬间看到尚未完成的末行；官方规范化读取器负责处理这一存储层细节。[当前 writer](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/rollout/src/recorder.rs#L1932-L1966)
- 旧历史事件可能没有 item 级开始/结束时间，规范化 schema 因而保留可空时间。[当前 legacy 说明](https://github.com/openai/codex/blob/66919805ea080053d1933b6b43afeb0d8bf70c91/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L1453-L1461)

这些兼容分支直接证明：复制当前 Rust struct 为 Swift `Codable` 并不构成稳定读取契约。

## 脱敏本机结构核验

在本机默认 Codex Home 上执行了只输出布尔值、文件数量、JSON 顶层键名和 payload 键名的结构检查；未输出或保存任何聊天正文、字段值、API 密钥或绝对会话路径。

核验结果与上游当前实现一致：当前与归档目录均存在；样本为纯 `.jsonl`；根目录存在 `session_index.jsonl`；rollout 顶层类型包括 `session_meta`、`event_msg`、`response_item`、`turn_context` 等。本机当前没有 `.jsonl.zst`，但这不否定上游已经支持压缩格式。

## 降级与兼容性信号

适配器必须把下列状态显式返回给 Store/UI，不能当作“当天没有聊天”：

| 信号 | 用户可见处理 |
| --- | --- |
| 找不到 `codex` 或无法启动 App Server | 提示安装/更新 Codex，并显示被尝试的来源类别；不要展示敏感完整 PATH |
| `CODEX_HOME` 不存在或不可读 | 指向设置中的目录选择，并保留原配置供修复 |
| initialize 或 `thread/list` / `thread/read` 返回 method/schema 错误 | 标记 Codex 版本不兼容，提示更新；保留错误 code，不记录响应正文 |
| 单个 thread 读取失败 | 其余线程继续；该线程显示“无法读取”并可重试 |
| `Turn.startedAt == null` | 显示“旧记录：日期精度不足”，允许手动纳入，不静默猜日 |
| 未知 `source` / `threadSource` / item type | 保留未知值的类别名用于诊断，默认不把内容送给 AI |
| App Server 进程退出或超时 | 取消当前扫描，指数退避重试一次；仍失败则让用户重试 |
| 只有云端、无本机线程 | 明确说明首版只读取本机已同步记录 |

JSON-RPC 客户端应忽略未知响应字段，对文档允许为空的字段保持 optional，并以“方法是否成功”而不是 `cliVersion` 字符串比较做能力探测。开发时可用目标 Codex 二进制运行 `codex app-server generate-json-schema` 生成测试 fixture；官方说明生成结果与该二进制版本精确匹配。[官方 schema 生成说明](https://learn.chatgpt.com/docs/app-server#message-schema)

## 明确不可依赖的推断

- 目录日期或 rollout 文件名日期等于用户选择时区中的报告日。
- 文件 mtime 等于最后一条用户消息时间。
- 第一条 `response_item` 就是用户首条可见消息。
- `updatedAt` 等于用户活动时间。
- `preview` 永远是显式线程名。
- 没有 `parentThreadId` 就一定是人工会话。
- 当前本机没有 `.zst`，所以未来也不会出现。
- 未识别的新字段/类型可以安全发送给 AI。
- 直接读取 `session_index.jsonl`、SQLite 表或 rollout 私有字段能跨 Codex 版本稳定工作。

## 交给后续规格的决定输入

本研究把以下边界留给后续产品/架构 ticket，而不是在存储层自行猜测：

1. 产品是否接受“跨午夜的同一 turn 按 turn 开始日归属”；若不接受，首版需求必须收窄或等待官方逐消息时间接口。
2. 当 `startedAt` 缺失时，UI 是默认排除还是默认勾选并警告。
3. 如何发现用户安装的 `codex` 可执行文件，以及最低兼容版本/更新引导。
4. AI 请求包含哪些 item 类型；建议默认只包含 user/agent 的文本，图片、音频、工具输出和 reasoning 需单独决定。
5. `cwd` 在 UI 中如何脱敏、如何把多个 worktree 聚合成同一项目。

