# 日报隐私出口与组合回归

本契约承接 [#34](https://github.com/PerryFinn/random-thoughts/issues/34) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20)。沿用已确认的 `DailyReportFlow` 动作／状态接口，组合真实 SQLite、CryptoKit、离线 tokenizer、三协议 Adapter 与 CocoaLumberjack；系统边界只接合成 stdio、受控 HTTP 和内存剪贴板接收器。不新增产品决策、迁移、正文档案或恢复机制。

## 出口契约

| 出口 | 允许 | 禁止 |
| --- | --- | --- |
| 窗口内存 | 各日期草稿、基线、候选、固定快照、整份草稿来源；当次请求响应和中间事实 | 真正关闭后恢复，保存后恢复旧来源 |
| SQLite／必要 journal | 明确保存的原始 Markdown、自身报告日与保存／编辑时间、当前设置、凭据密文 | 草稿、基线、会话／来源／生成档案、完整请求响应、中间事实、凭据明文副本（用户明确保存的原文例外） |
| UserDefaults／辅助文件 | 既有其他功能数据；无内容目录锁及必要事务状态 | 日报配置副本、草稿恢复、请求缓存、诊断包、自动备份 |
| 配置校验网络 | 少量合成内容、必要协议字段、原生鉴权 | 工作正文、生成偏好、历史、来源元数据、重定向、自动重发 |
| 生成网络 | 主动当前端点、必要正文／偏好／历史副本、临时编号、必要日期时区、原生鉴权 | 额外真实来源 ID／标题／目录、自动换端点／协议、自动重试、请求磁盘缓存 |
| 预览 | 本机 `AttributedString`／`Text`，显式点击允许的链接 | HTML／脚本执行、WebView、自动远程资源、查看来源时重读 Codex |
| 明确保存／显示／复制 | 原样手写正文及潜在秘密；主动显示／复制可读 Key；删除后保留既有剪贴板 | 暗中脱敏、自动复制、附加来源／质量信息 |
| 日志／诊断 | 下列固定白名单事件、枚举及必要聚合数值 | 正文、偏好、报告日键、模型、端点／query、来源／任务 ID 与哈希、配置指纹、Key／密文／内置密钥、原始 Error／stdio／请求响应、任意 metadata |

尽力脱敏发生在固定快照前、每次实际外发副本、结果成为草稿前。专用 Key 精确遮盖与高置信规则分开处理；人名、邮箱、项目及正文自然出现的普通路径保留。失败以非阻断提示继续，固定快照不重写；手写保存／复制原样，以后作为历史外发才处理副本。标记未命中不代表所有秘密已清除。

## 日志白名单

业务入口只接类型化事件，不接自由文本、`Error`、`URL`、配置、`Data` 或任意字段字典。

| 事件 | 唯一专属字段 |
| --- | --- |
| `window_mode_changed` | `mode` |
| `codex_check_finished` | `result error version`，版本只取解析后的数字 |
| `session_scan_finished` | `result candidates succeeded failed` |
| `ai_validation_finished` | `service stage result capability` |
| `report_generation_started`／`report_generation_stage_changed`／`report_generation_finished` | `path stage result input_tokens reason plan_min plan_max layer completed in_flight tokenizer` |
| `report_storage_finished` | `operation result schema credential_format` |

整个 `DDLogMessage` 的 format 与最终 public 文本均须满足固定事件和字段集合；`file=fileName=DailyReports`、`function` 为固定事件、`line=0`、`context=0`、`representedObject`（tag）为空，level／flag 为 info，无 formatter。框架时间、线程、队列及 QoS 仅作系统元数据，不改造成来源标识。

生产只注册一个 `DDOSLogger`，subsystem=`com.perryfinn.random-thoughts`，category=`DailyReports`。两个解析文件固定 CocoaLumberjack 3.10.0（`b75d3c3198a2930b4491b04fd47cb504b359c750`）及 swift-log 1.16.1；应用只链接 CocoaLumberjack 产品。核对该版本 `DDOSLogger` 使用 `%{public}s`，无文件／网络 logger、自有上传或正文控制台出口。隔离集成使用独立 `DDLog` 和线程安全内存 logger；生产者结束后在日志队列外 flush 该实例，不代表 OSLog 已落盘。

## 测试边界与合成材料

沿用父规格已确认的主接口，不为内部方法新增替身。标记分别区分工作正文、生成结果、历史／草稿、偏好、来源标题／ID／目录、报告日、完整端点／query、模型、专用 Key、密文／测试密钥、原始错误及 stdout／stderr。正文自然路径与额外来源路径使用不同标记。逐出口允许必要字段，不能用统一禁词表误判明确保存或原生鉴权。

`AIServiceAccess`、`CodexSourceAccess`、`AICredentialAccess` 显式为 `nonisolated`／`Sendable` 的异步外部边界，允许独立 actor 执行；流程、设置和视图状态仍由 MainActor 管理。此声明也用于避免 Swift 6.4 将协议本身推断为 MainActor，阻止跨模块测试 actor 遵守协议。测试替身在扩展中声明协议遵守，避免当前编译器在跨文件调用先于 actor 声明时错误地给 actor 推导 `nonisolated`。

`DailyReportPrivacyIntegrationTests` 串联三协议的校验、直接／提取／归并／成文与真实存储、加密、分词、日志。合成 HTTP 按原生请求产生响应，不复制生产调度或覆盖算法。另覆盖跨日期草稿、独立设置窗口、保存失败／重试、删除／清空、关闭重开、明确复制及历史副本再遮盖；现有受控时钟／迟到回调及合成 stdio 回归共同构成下表。

## 父规格最低覆盖矩阵

每行列出实际套件／测试名、合成输入和预期。自动化结果以本次 Debug／Release 全套记录为准；M 项由 #35 的人工检查承接，不写成通过。

| 范围 | 名称 | 输入 → 预期 | 自动化结果 |
| --- | --- | --- | --- |
| 日期与文本纳入 | `ReportDayTests`、`CodexSessionWireTests.mixedWireKeepsOnlyOrderedTextAndFinalAnswersAndNeverReadsInternalSources` | DST／跨午夜／混合项 → 半开归日，仅用户正文和 final | Debug／Release 全套通过 |
| 来源与快照 | `CodexSessionFlowTests`、`CodexSessionPrivacyTests` | 刷新／选择／不同 worktree → 固定快照，关闭不恢复 | Debug／Release 全套通过 |
| Codex 读取 | `CodexStdioTests`、`CodexSessionWireTests` | 合成 wire／原始错误／stdio → list/read，固定错误，无私有 fallback | Debug／Release 全套通过 |
| 发现、扫描及锁 | `CodexSourceDiscoveryTests`、`CodexScanLockTests`、`CodexSessionWireTests` | 无效目录／不完整范围／竞争 → 不回退，完整性与状态分开 | Debug／Release 全套通过 |
| 三协议请求／解析 | `DailyReportPrivacyIntegrationTests`、各协议 Wire／Stream 测试 | 三协议与多阶段 → 原生字段／鉴权，来源元数据不外发 | Debug／Release 全套通过 |
| 校验、资格、基线 | `ChatCompletionsValidationTests`、`ResponsesFlowTests`、`MessagesFlowTests` | 三探测／基线变化 → 纯合成，不自动当前或生成 | Debug／Release 全套通过 |
| 六章节与完成状态 | `ReportPayloadTests`、三协议 Stream／Error 测试 | 完整／拒绝／截断／坏结构 → 原子完整草稿或保留原稿 | Debug／Release 全套通过 |
| 预算与 tokenizer | `OfflineTokenizerTests`、`ReportGenerationConfigurationTests` | 官方差分／双编码／失败 → 真离线计数，不外发估算 | Debug／Release 全套通过 |
| 辅助、分批、覆盖 | `ReportBatchContextTests`、`ReportBatchGenerationTests` | 历史／超长轮次／密集摘要 → 当天全覆盖，有限归并 | Debug／Release 全套通过 |
| 调度与配置竞争 | `ReportBatchGenerationTests`、`ReportGenerationLifecycleTests` | 4／5 次／并发／配置变化 → 有效确认与启动配置固定 | Debug／Release 全套通过 |
| 失败、取消、超时 | `AIHTTPTests`、`ReportGenerationLifecycleTests` | 重定向／限流／取消／迟到 → 不自动重发，保留原稿 | Debug／Release 全套通过 |
| 草稿与保存 | `DailyReportContentTests`、`DailyReportPrivacyIntegrationTests` | 多日期／手写秘密／提交失败 → 原样保存复制，失败留草稿 | Debug／Release 全套通过 |
| 临时来源 | `ResponsesPrivacyTests`、`MessagesPrivacyTests`、`DailyReportPrivacyIntegrationTests` | 生成／编辑／保存／关闭 → 整份来源只随草稿，不入库或 Markdown | Debug／Release 全套通过 |
| SQLite／凭据／迁移 | `AIServicePersistenceTests`、`AICredentialTests`、`ReportStorageManagementTests` | 真事务／随机 nonce／认证错／合成旧库 → 原子提交或保留原数据 | Debug／Release 全套通过 |
| 删除／重置／恢复 | `ReportContentManagementTests`、`ReportStorageManagementTests`、`DailyReportPrivacyIntegrationTests` | 合成删除／旧回调／中断 → 确认范围，无旧内容回填或自动网络 | Debug／Release 全套通过 |
| 窗口／设置／生命周期 | `DailyReportWindowTests`、`DailyReportSettingsTests`、`DailyReportLayoutTests` | 双窗口／跨日期／最小尺寸 → 状态保护，无窗口 NSHostingView 测量 | Debug／Release 全套通过 |
| 隐私／日志 | `DailyReportTelemetryTests`、各 Privacy 测试、`DailyReportPrivacyIntegrationTests` | 分立标记／遮盖失败／日志对象 → 逐出口断言、精确白名单 | Debug／Release 全套通过 |

实际命令、配置、依赖证据及未执行项见 [testing.md](testing.md)。生产纯构建与隔离 U/I/L／隐私回归均须在 Debug／Release 对应配置执行；Debug 测试或 Rust 优化内核不能替代 Release Swift 测试。
