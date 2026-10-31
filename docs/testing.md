# 构建与隔离测试

本入口承接 [#21](https://github.com/PerryFinn/random-thoughts/issues/21) 至 [#36](https://github.com/PerryFinn/random-thoughts/issues/36) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20) 的测试隔离要求。生产构建、隔离 U/I/L、会启动应用的系统/UI 验收分别执行。#28 的直接生成、真实离线 tokenizer 与协议假服务边界见 [chat-completions-generation.md](chat-completions-generation.md)，#29 的原生 output／SSE、配置与共享流程边界见 [responses-generation.md](responses-generation.md)，#30 的原生 Messages 内容块／thinking／SSE 边界见 [messages-generation.md](messages-generation.md)，#31 的完整输入、规模确认和受控并发见 [long-input-generation.md](long-input-generation.md)，#32 的配置竞争、取消、错误与手动重试见 [generation-lifecycle.md](generation-lifecycle.md)，#33 的内容删除、专用库迁移／重置与人工整体恢复见 [daily-report-storage-management.md](daily-report-storage-management.md)。

隐私出口、精确日志白名单和父规格最低覆盖矩阵见 [daily-report-privacy.md](daily-report-privacy.md)。

[#35 验收入口](acceptance/issue-35/README.md) 提供人工清单、纯合成材料及[记录模板](acceptance/issue-35/record-template.md)。三档离线性能、硬约束及完整 App 包体增量已实测，见[离线验收记录](acceptance/issue-35/offline-performance.md)；真实 Codex、原生交互、截图及 #36 仍未完成，不能据此声明 #35 或父规格验收通过。

[#36 语义验收入口](acceptance/issue-36/README.md) 复用既有直接语义夹具，提供[固定八场景](acceptance/issue-36/scenarios.md)、判定规则、调用规模／授权清单及[三协议 48 任务空白模板](acceptance/issue-36/record-template.md)。用户补充提供 Key 并授权两个 OpenAI 协议的真实请求后，使用 `./script/test-live-openai.sh scenarios` 显式执行；默认隔离入口仍断网且跳过 live 测试，不自动加载 `.env.local`。Messages、原生应用、真实 Codex 和用户数据库操作仍不在本轮授权内，未实测项保持未完成。

## #36 S08 结果范围与真实多层验证（2026-10-31）

基于 `8ec4fb9`，从 CC-S08 sign-off 范围缩窄诊断，缩至抽取四轮及直接成文两轮；校正了把进度编号误当因果范围的旧判据，原失败不改记通过。抽取／归并和成文分别约束原因果句、不同完成状态及具体对象的结果范围，既不扩大文档完成，也不因其他工作待审降成草稿。真实多层又复现了归并引用越界：两个节点即足以触发，只有指令修改仍失败；节点输入因此不再携带已完成校验的旧 `references`，只保留 `turns`／`status`／`summary`。响应字段和 schema、覆盖、引用及整轮状态拒绝检查不变，没有自动修复或额外审核请求。

| 实际命令／检查 | 结果 |
| --- | --- |
| 定向事实／成文契约与节点编码回归 | 均先出现预期失败再实现；旧引用输入边界 16 处失败、未限定发布示例 20 处失败、保持已完成结果 12 处失败后转绿。测试验证请求契约及原拒绝行为，不证明模型语义。 |
| `./script/test-live-openai.sh s08-state-minimum`，G14 | 3 探测＋2 抽取＋2 直接成文；未明确范围与跨句明确仅 B16-4 的对照通过，全文仍记录章节质量损失。 |
| `./script/test-live-openai.sh s08-merge-minimum`，G17 | 3 探测＋3 组件请求；当前节点与旧片段 ID 不重合，覆盖、引用及轮次关联信号通过；组件不替代完整执行器校验。 |
| `./script/test-live-openai.sh s08-blockers`，R11 | 原 C＝12,000、CC／RS 各两次，6 探测＋28 生成；有限范围／完成状态目标 4／4，全文 2 失败／2 降级（含空章仅为 `-` 的模板失败），实际 0 层，非正式 S08 通过。 |
| `./script/test-live-openai.sh s08-layered`，R12 | 相同全量材料仅 C 改为 9,550，6 探测＋116 生成；四次均实际 2 层、无请求错误。有限目标 4／4；全文 3 失败／1 降级，含 schema 被扩成发布阻塞原因的硬违规，S08 仍未通过。 |
| `./script/test-isolated.sh --configuration Debug`／`Release` | 各 58 套件／285 项登记、3 项跳过、282 项执行通过，无 Swift 编译警告。 |
| `./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，纯构建；保留既有环境诊断及 AppIntents 元数据提示。 |
| `bash -n script/test-live-openai.sh`、本地 Markdown 链接、Key 扫描、`git diff --check` | 通过；旧调用记录逐字前缀保留，工程排序改动哈希不变并排除。 |

完整诊断、所有候选与逐次判定见[真实记录](acceptance/issue-36/live-openai.md)。本轮 26 个目录共 **611 笔客户端尝试（93 探测＋518 生成，含 16 取消）**，累计 **1,258 笔**，原 D00 最多 3 笔仍未确认；usage／费用未测。原 C＝12,000、早期 C＝8,000 和当前 C＝9,550 各自保留，不能混记。临时扫描、单次限制和调试探针已删除，移除了外发节点中不再需要的旧引用；没有删除既有文件、旧失败或用户数据。未启动应用、未读真实 Codex、未操作用户数据库，不推送、不评论、不关票。真实多层路径已验证，因果和章节质量及其他旧语义问题仍在，#36／父 #20 继续未完成。

## #36 S08 共享 schema 阻塞修复验证（2026-10-31）

基于 `b76cce4`，先从完整 CC-S08 复现，缩至 B08-1／B08-4／B16-4 三轮；两轮对照不复现。边界计数确认原因果句可以仍在抽取结果中，但与 B08 草稿／审核进度混在同一事实，最终成文便把来源条目当成影响范围；单改成文规则的多版候选仍失败。最终同时约束抽取／归并与成文：因果阻塞独立成事实，优先保留，范围未明确时保留原指代及未知范围；成文不从来源编号推断影响对象，也不强行扩大到全部规则。主契约先更新，直接／分批请求规则均先观察预期失败再实现；覆盖、引用、整轮状态、schema 和预算检查不变。完整过程与所有失败见[逐次记录](acceptance/issue-36/live-openai.md)。

| 实际命令／检查 | 结果 |
| --- | --- |
| `./script/test-isolated.sh --filter 'ReportSemanticFixtureTests\|ReportFactContractTests'` | 各版规则均先出现预期缺失断言失败；抽取独立事实、优先保留及未知范围规则也分别先红后绿。最终 2 套件／4 项登记通过；它们验证实际请求契约和渲染，不证明模型语义。 |
| `./script/test-isolated.sh --filter 'LiveOpenAISemanticTests\|ReportAcceptanceScenarioTests'` | 离线规划为两协议每次 7–9 笔、6 提取、最多 1 层；三轮两对照均为直接 1 笔。缩减夹具验证只修改局部范围一句、canonical 字节不变。 |
| `./script/test-live-openai.sh s08-minimum`，F21 | 最后三轮直接对照：3 探测＋2 生成，未点名集合与跨句明确仅 B08-4 均保留；它验证共用成文规则，不能替代完整场景。 |
| `./script/test-live-openai.sh s08-blockers`，R03–R06 | 每批均 6 探测＋28 生成；即使有限断言或共享目标偶有通过，全文仍有失败，未记作最终成功。F22 又观察到阻塞与草稿混写；F23 只要求拆分事实后直接遗漏 schema，命令退出 1，失败保留。 |
| 完整 CC-S08 单次诊断，F24 | 3 探测＋7 生成；抽取及成文输入均为独立 schema 阻塞事实，原句及未知范围保留、不混入条目进度，最终共享范围目标通过；不替代正式复测。 |
| `./script/test-live-openai.sh s08-blockers`，R07 | 最终完整 v1 CC／RS 各两次，6 探测＋28 生成；有限断言通过，全文核对共享 schema 原因及范围目标为 4／4。全文为 3 失败／1 降级，包含 sign-off 范围及概览扩大完成范围等问题，且实际均 0 层；完整 S08／#36 未通过。 |
| `./script/test-isolated.sh --configuration Debug`／`Release` | 各 58 套件／281 项登记，3 项显式入口跳过，278 项执行通过；无 Swift 编译警告。 |
| `./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`；纯构建，保留既有 CoreDevice／CoreSimulator 环境诊断与 AppIntents 元数据提示。 |
| `bash -n script/test-live-openai.sh`、本地 Markdown 链接、`git diff --check` | 通过；原调用记录为逐字前缀保留，工程排序改动哈希不变并排除，修改文件不含 Key。 |

本轮 **319 笔 HTTP（102 探测＋217 生成）** 均计入记录（含失败候选），累计 **647 笔已确认**，原 D00 最多 3 笔探测仍未确认，usage／费用未测。临时缩减变体、诊断模式与 `[DEBUG-S08-*]` 探针已删除；没有删除既有文件、用户数据或旧失败。显式保留最小对照和完整受影响场景入口，默认隔离测试不读 Key、不发真实请求。未启动应用、未读真实 Codex、未操作用户数据库，不推送、不评论、不关票；其他遗留问题、S08 多层、Messages 与用户人工验收继续未完成。

## #36 S07 未认可计划修复验证（2026-10-31）

基于 `19cc50a`，先用完整 CC-S07 复现，再缩至一个轮次、三片／四笔生成；两次缩减调用均在成文阶段新增行动，上游仍保留未执行状态，分批没有漏传共用指令。根因是成文契约未明确区分未解决状态与获认可未来行动。先更新长输入契约，并观察直接／分批请求契约回归共 30 处预期失败，再补四行共用指令；覆盖、引用、整轮状态及预算检查未改。既有明确计划夹具与生成结果原样保留，不新增语义过滤或 AI 修复。

| 实际命令／检查 | 结果 |
| --- | --- |
| `./script/test-isolated.sh --filter 'ReportSemanticFixtureTests\|ReportFactContractTests'` | 修复前 30 处缺少规则的断言失败；修复后 2 套件／4 项登记通过，包含三协议预算及两种分批契约参数。 |
| 临时 CC-S07 缩减真实回归 | 修复前连续两次新增未认可行动；仅修改共用指令后计划为空。所有缩减／探测尝试分别保留，见[真实记录](acceptance/issue-36/live-openai.md)。 |
| `./script/test-live-openai.sh s07-plans` | 原完整 v1 CC-S07／RS-S07 各两次；6 笔探测＋60 笔生成。目标 4／4 无新增未认可行动；严格空章断言因一次原文状态错章而退出 1，原失败保留，未冒充命令通过。全文 Agent 复核 1 通过／3 降级，用户人工未执行。 |
| 有限判据对保留合成报告的离线重放 | 旧 E01／E04–E06 四份新增行动仍全部拒绝；E07 及 R02 四份目标结果接受。允许逐字未执行状态属于校准判据范围，不是产品过滤；校准后未追加真实请求，不宣称新版 live 命令已实际通过。 |
| `./script/test-isolated.sh --configuration Debug` | 58 套件／279 项登记，两个性能入口和 live 共 3 项跳过，276 项执行通过。 |
| `./script/test-isolated.sh --configuration Release` | 同样 58 套件／279 项登记、3 项跳过，276 项执行通过。 |
| `./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，未启动应用。没有 Swift 编译警告；保留既有 CoreDevice／CoreSimulator 环境诊断及 AppIntents 元数据跳过提示。 |
| `bash -n script/test-live-openai.sh`、本地 Markdown 链接、`git diff --check` | 通过；原 P01–P03／R01 记录逐字保留，工程排序改动哈希不变并排除。 |

临时缩减、分类统计、计划打印及全部 `[DEBUG-S07-*]` 插桩已删除；显式 `s07-plans` 只跑完整 S07，默认隔离测试不读 Key、不发真实请求。未删除已有文件、数据库或用户内容；未启动应用、未读真实 Codex、未操作用户数据库。不修复／复测 S08 和其他场景，旧失败及其他未完成项继续保留，#36／父 #20 仍未完成；不推送、不评论、不关票。

## #36 S07／S08 invalidResponse 修复验证（2026-10-30）

基于 `bfa7d0d`，只修复分批事实请求的两项契约缺口：部分轮次仍能选择 `confirmed`、数字片段编号可冒充轮次关联。先从 CC-S07／CC-S08 的真实合成调用复现，再缩小到两片同轮／单个错误关联；`ReportFactContractTests.schemaCompliantExtractionCannotChooseTheObservedInvalidStatusOrTurn` 先因 `invalidResponse` 和缺少关联字段失败，再完成实现。`wholeTurnsKeepConfirmedAvailableWhilePartialMergesCannotChooseIt` 验证完整轮次与部分归并，`partialTurnSchemaFitsTheFullSchemaReservation` 核对三协议的双编码预留。既有坏覆盖／引用／整轮状态拒绝测试继续通过，新增数字关联拒绝参数；没有放松执行器检查或添加修复请求。

| 实际命令 | 结果 |
| --- | --- |
| `./script/test-live-openai.sh invalid-response` | 6 任务全部成文、无 `invalidResponse`；6 笔探测＋74 笔生成，无错误／取消／重试。Agent 语义复核仍为 1 降级通过、5 失败，逐次结果及全部诊断尝试见[记录](acceptance/issue-36/live-openai.md)，原 P01–P03 保留。 |
| `./script/test-isolated.sh --configuration Debug` | 58 套件／279 项登记，两个性能入口和 live 共 3 项跳过，276 项执行通过；无 Swift 编译警告。 |
| `./script/test-isolated.sh --configuration Release` | 同样 58 套件／279 项登记、3 项跳过，276 项执行通过；无 Swift 编译警告。 |
| `./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，没有启动应用；保留既有 CoreDevice／CoreSimulator 环境诊断及 AppIntents 元数据跳过提示。 |
| `bash -n script/test-live-openai.sh`、Markdown 本地链接与 `git diff --check` | 通过。 |

临时重放测试、诊断模式、响应采集及 `[DEBUG-36]` 插桩已删除；默认测试仍不读取 Key 文件或调用真实服务。没有删除数据库或用户内容，没有兼容／迁移。未启动应用、未读真实 Codex、未操作用户数据库；原工程排序改动保留并排除。新增计划、关键阻塞语义及 S08 多层覆盖未在本轮修复，#36／父 #20 仍未完成。不推送、不评论、不关票。

## #36 OpenAI 真实调用与验收入口（2026-10-30）

基于 `9c5e5b1` 增加显式 hostless 真实调用入口，复用生产统一流程、AI Adapter 和完整 v1 合成材料；没有改生产生成指令、校验、协议或存储。两个官方 OpenAI 组合各跑八场景两次，实际 32 任务、88 笔 HTTP 尝试（含配置探测、取消及一次采集失败后的重跑）。逐次 Agent 文本复核为 12 通过、5 降级、15 失败，详见[真实调用记录](acceptance/issue-36/live-openai.md)；运行时结构通过不能替代语义通过。

| 实际检查 | 结果 |
| --- | --- |
| `./script/test-live-openai.sh probes` | 两协议共 6 笔真实基础／流式／结构化探测通过。 |
| `./script/test-live-openai.sh scenarios`，首次 | 6 笔探测通过；首个生成成功后，采集器原子写入越出沙盒测试根而失败；保留判定未完成。 |
| `./script/test-live-openai.sh scenarios`，采集修正后 | 6 笔探测通过；32 任务全部尝试，24 次 `success`、2 次 `degraded`、6 次 `invalidResponse` 失败，命令退出 1；语义结论按逐份复核，不能写成测试通过。 |
| `./script/test-isolated.sh --configuration Debug` | 57 套件／276 项登记，3 项显式入口跳过（两个性能入口及 live），273 项执行通过。 |
| `./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，生产纯构建；未启动应用。 |
| `bash -n script/test-live-openai.sh` | 通过。 |

新增隔离检查验证缺失历史不补位、超长单轮完整 UTF-8 字节拆片、多会话当天完整处理及跳过大辅助单元后仍使用短历史。正常测试不读取环境文件、不调用外网；真实入口构建后才读入 Key，并使用单独 live profile。未执行 Messages、用户人工复核、真实 Codex、UI／系统／截图或用户数据库操作；本轮不重复无生产改动的 Release／性能测量。没有删除已有代码、文件或用户数据；起始工程排序改动保留并排除。

## #36 离线验收准备验证（2026-10-30）

基于 `9d8b141cf4873837ff13c2a5b8aefe87433e3173`，只增加验收文档和模板，复用 `direct-report-semantics.json`；没有改生产代码、已有夹具、测试、依赖、工程或存储契约。#36／父 #20 正文与评论、CONTEXT、三份 ADR 及隔离入口已核对；远端 main 为 `6f41f8a`，#36 仍被 OPEN 的 #34 阻塞，#34 的 #29／#30／#32／#33 也仍 OPEN，本地前置实现均为基线祖先。此处不解除远端阻塞。

| 实际检查／命令 | 结果 |
| --- | --- |
| 仓库文档的本地 Python 只读检查 | 固定八场景名称／语言／路径、48 个唯一槽位及每场景两次、全部未执行状态、复用夹具名称、测试名称、Markdown 本地链接／表格列数、C／O／I 算术均通过；不是新增场景的装载或语义实测。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter 'ReportSemanticFixtureTests\|ReportBatchGenerationTests\|ReportBatchContextTests'` | 3 套件、18 项通过；使用既有夹具／受控 AI，覆盖直接材料、拆片、有限归并、辅助完整单元裁剪机制。 |
| `rtk proxy ./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`；arm64 Debug 生产纯构建，不启动应用。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug` | 55 套件、272 项登记；2 个显式性能压力入口按默认配置跳过，270 项执行通过，退出 0。 |

环境为 Apple M3 Max／36GiB、arm64、macOS 27.2（26B123）、Xcode 27.1（27A9275）。没有 Swift 编译警告；生产构建保留既有 CoreDevice／CoreSimulator 环境诊断及 AppIntents 元数据跳过提示。本轮只有文档变化，不重复 Release／性能测量，也不把 #35 的既有性能结果算作 #36 新场景或真实语义证据。

提交前按 `9d8b141` 评审本票四份暂存文档。Standards 为 0 项规范违反／可行动气味；Spec 初审 1 项已解决：S04 的明确审阅请求与“无计划”判定冲突，改成仅陈述冲突证据的输入后复核为 0 项未解决。最终文档检查确认 48 槽位均未执行、引用及暂存内容一致；`rtk proxy git diff --cached --check 9d8b141` 通过。

没有删除已有代码、文件、数据库或用户数据。起始 `project.pbxproj` 两处排序改动保留并排除，SHA-256 仍为 `ae1aa7492c840053d3114b948f5437dc66323aee0fac302c326184e090ad6c1b`。未启动应用，未运行旧宿主／UI 测试，未访问真实 Codex／AI 或操作用户数据库。真实组合／能力、合成材料实际装载／路径／调用数及 48 次人工判定全部未完成；#36 和父 #20 不得宣称验收通过。本轮仅本地提交，不推送、不评论、不关票。

## #35 离线性能与包体验证（2026-10-30）

基于 `6f41f8a9e60d3c1356b0afec274734766114a30e`，仅新增隔离测量入口及聚合记录，没有改生产源码、资源、Xcode 工程或产品契约。执行前只读核对 #35 OPEN 且被 OPEN 的 #34 阻塞，#34 的 #29／#30／#32／#33 也仍 OPEN；相应本地实现均为起点祖先。本次不解除远端阻塞、不更改 Issue 状态。

实测为 Apple M3 Max、36GiB、arm64、macOS 27.2（26B123）、Xcode 27.1（27A9275）、Swift 6.4、macOS 27.0 SDK。沿用隔离沙盒，性能模式额外禁止全部网络；压力测试只执行合成 stdio 子进程及受控 AI Adapter，不打开数据库、不启动生产应用。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter ReportAcceptanceMaterialTests`（最终） | 1 套件、4 项通过；新增 wire 回归曾先因空扫描结果实际失败，接线后通过。 |
| `rtk proxy ./script/measure-report-performance.sh`（阶段矩阵） | 三档 scan／tokenize／plan 及并发 1／3／8 schedule 的首次／重复共 36 条样本，加 9 条调度准备样本；退出 0。 |
| `rtk proxy ./script/measure-report-performance.sh all constraints` | 三档必要失败、取消后迟到成功全部通过；每种情况仅初始 3 笔请求，无后续派发或部分返回。最终默认入口也包含此检查。 |
| `rtk proxy ./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，生产 Debug 纯构建。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug` | 55 套件、272 项登记；2 个显式压力入口跳过，其余 270 项执行通过，退出 0。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release` | 55 套件、272 项登记；相同 2 项跳过，其余 270 项执行通过，退出 0。压力入口已由独立测量命令实测。 |
| `rtk proxy bash -n script/measure-report-performance.sh script/test-isolated.sh` | 通过。 |

功能前 `123948d` 与候选 `6f41f8a` 由干净归档、同一 arm64 Release／禁签名参数分别纯构建，均成功。完整 `.app` 逻辑字节由 3,041,091 增至 16,849,331，增加 13,808,240 字节；磁盘占用增加 13,811,712 字节。精确命令、二进制 SHA、资源拆分、45 条原始聚合样本、3 条故障检查及峰值口径均见[离线验收记录](acceptance/issue-35/offline-performance.md)。

记录保留初次编译、合成标题规范化及沙盒相对导入失败，不把失败尝试计为样本。Debug／Release 最终回归验证完整输入、独立协议块、原正文／来源原子保护、密集归并、无缩减拒绝、必要失败与取消后迟到结果；压力样本返回空合成事实，不能评价真实模型语义或延迟。RSS 为进程累计高水位，包含框架、材料及准备；重复值继承首次峰值，扫描父／子分别报告，不声称是阶段增量或同时峰值。

纯构建只有既有 CoreDevice／CoreSimulator 环境诊断及 AppIntents 元数据跳过提示，没有 Swift 代码警告。没有删除已有文件或用户数据；开发中新增的无效沙盒导入配置已删除，最终沿用现有 profile。既有 `project.pbxproj` 两处排序改动保留并排除。本轮仍未执行真实 Codex／AI、原生 UI／系统／可达性／截图、最低 macOS 26.5、OSLog 落盘及 #36；未实测项保持未完成。

提交前两轴独立 code-review：Standards 为 0 项文档标准违规、0 项可行动代码气味；Spec 为 0 项可行动问题。`git diff --cached --check 6f41f8a` 通过，未将离线完成扩大为 #35 或父 #20 整体验收通过。

## #35 验收准备记录（2026-10-25）

基于本地 `c74eb42c4050f69e742c4aed56c8f5e5f703f2fd`，只准备清单、合成材料与记录模板，不改生产代码或存储契约。已读 AGENTS、#35 与父 #20 的完整正文／评论、CONTEXT 和三份 ADR；本地 #29–#34 提交均为基线祖先。只读查询远端 main 为 `123948d`，#35 仍被开放的 #34 阻塞，#34 的 #29／#30／#32／#33 也仍开放。本地准备不解除远端阻塞，不操作 Issue 状态。

实测构建环境：Apple M3 Max、36GiB、macOS 27.0.1（26A434）、Xcode 27.1（27A9275）、Swift 6.4（swiftlang-6.4.0.34.1）、arm64。此处是构建／隔离环境记录，不代表当前系统或最低 macOS 26.5 的原生交互验收。

`acceptance-35.json` 完全手工合成，版本 1、种子 35；包含当前／归档会话的正常交互提示词、允许事实与禁止结论、UI Markdown 和压力规模定义。测试专用 `ReportAcceptanceMaterials` 生成生产候选／工作轮次值；三档严格为 10／100／1MiB、100／1000／10MiB、1000／10000／100MiB，中大首轮 2MiB，UTF-8 总量包含用户及最终回复正文。只生成测试内存材料，不构造真实 Codex 私有文件，不将压力材料外发。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter ReportAcceptanceMaterialTests`（首次） | 1 项测试实际执行，因缺少材料资源的 `#require` 失败，退出 1；加入纯合成定义后通过。 |
| 同一材料定向命令（最终） | 1 个套件、3 项通过：定义与规格规模、全部规模／精确字节／Unicode／稳定重建、统一流程扫描确认与快照保持；无真实 Codex／AI 请求。 |
| `rtk proxy ./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，生产 arm64 Debug 纯构建。 |
| `rtk proxy ./script/build.sh --configuration Release` | `BUILD SUCCEEDED`，生产 arm64 Release 纯构建。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug` | 53 个套件、269 项通过。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release`（首次） | 53 个套件、269 项中 1 项失败：既有 `AIHTTPTests.aLegalStreamTerminatorCompletesWithoutWaitingForTheConnectionToClose(.messages)` 抛出假服务 `.setup`；退出 1，不能记通过。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release --filter 'AIHTTPTests.aLegalStreamTerminatorCompletesWithoutWaitingForTheConnectionToClose'` | 定向复测 1 项、3 个协议参数全部通过；未修改生产代码或原有 HTTP 测试。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release`（复跑） | 53 个套件、269 项全部通过，退出 0；首次 `.setup` 失败记录保留，具体底层原因未确认。 |

新增生成器测试先因尚无 `makeSessions` 接口编译失败；这是缺接口证据，不当作行为红绿证据。材料缺失的实际断言失败与其后通过单独记录。构建无 Swift 编译警告，保留既有 CoreDevice 插件／CoreSimulator 环境诊断和 AppIntents 元数据跳过提示；未安装组件或改变系统设置。

Release 首次失败属于本机回环假服务创建阶段；现有 `.setup` 没有保存底层 errno，不能断言具体是端口冲突或产品传输错误。定向复测通过后补跑一次 Release 全套，首次失败仍保留。完整运行中的阶段测试时间不作为性能实测。

code-review 固定起点为 `c74eb42`，先评审暂存的 6 个本票文件，再本地提交。Standards 为 0 项规范违反／可行动气味；Spec 初审发现 1 项 P2：模板混淆同进程重开窗口与重新启动应用的数据源状态。已拆为 C-06（重开不恢复快照、不自动重扫）与 C-07（重启回到未检查、无自动请求），复核后 Spec 为 0 项未解决缺失／错误／范围扩张。既有 `project.pbxproj` 两处排序变化保留并排除，SHA-256 仍为 `ae1aa7492c840053d3114b948f5437dc66323aee0fac302c326184e090ad6c1b`。没有删除现有代码、文件、数据库或用户数据，没有新增迁移、兼容路径、生产调试开关或运行档案。

未执行：生产应用启动、旧宿主／UI 测试、真实 Codex 版本检查／会话建立／读取、真实 AI、用户数据库操作、原生窗口／快捷键／Dock／登录启动／显示器改变／睡眠唤醒／系统剪贴板、截图、macOS 26.5 或当前开发系统人工验收、OSLog 实际落盘、扫描／双编码／规划／调度性能及最终 App 包体增量。完整性能 runner 尚未准备；模板中的所有实测项保持未完成。#36 的 48 任务语义验收未执行，#35 和父 #20 均未完成；不推送、不关闭票。

## #34 隐私汇合与双配置验证记录（2026-10-25）

基线为本地 `a62e7ec`。本机为 Apple Silicon、macOS 27.0.1（26A434）、Xcode 27.1（27A9275）、Swift 6.4（swiftlang-6.4.0.34.1）；系统默认仍选择 Command Line Tools，两个脚本各自指定 Xcode，不改全局选择。

已读 #34、父 #20 完整正文／评论及领域文档。本地 #29／#30／#31／#32／#33 的提交均为基线祖先；结束前只读复核远端 main 仍为 `123948d`，#34 及原生阻塞项 #29／#30／#32／#33 仍开放。本地完成不解除远端阻塞。保留并排除起始工程文件的键顺序改动，SHA-256 与起始一致。

核对两份 `Package.resolved`：CocoaLumberjack 3.10.0（`b75d3c3198a2930b4491b04fd47cb504b359c750`）、swift-log 1.16.1（`4038b6a4f74a1426f47eb1dd5b4bb5628a15d597`）。核对该 checkout 的 `DDOSLogger.m`：固定 subsystem/category 创建 OSLog，最终文本通过 `%{public}s` 输出；生产 `DailyReportTelemetry.makeSystemLog()` 只注册一个无 formatter 的 `DDOSLogger`。业务入口为专用事件类型，实际完整消息由独立日志实例捕获测试约束；不把框架 flush 等同于系统落盘。

只读核查日报存储和网络路径：单库及必要事务文件、不写草稿／来源／中间事实档案；传输创建无缓存／Cookie／凭据存储的会话，重定向回调拒绝目标，无自动重发或服务切换；预览使用 `SafeMarkdown`／`AttributedString`／`Text`，无 WebView 或自动资源加载。合成 stdio 的输入夹具位于测试目录，数据库置于独立子目录，避免把夹具本身误判为产品生成的副本。

| 实际命令／检查 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter everyTypedEventConformsToTheExactPublicWhitelist` | 真正执行后，三个生成事件的 `messageFormat` 精确断言失败；改为三个固定事件模板后通过，并纳入以下定向及全套回归。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter 'Privacy\|DailyReportTelemetryTests\|AIHTTPTests'` | 9 个套件、29 项测试通过，包含参数化三协议／直接与分批／遮盖失败／原始 stdio 及可缓存 GET。 |
| `rtk proxy ./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，仅 arm64 Debug 生产应用纯构建。 |
| `rtk proxy ./script/build.sh --configuration Release` | `BUILD SUCCEEDED`，仅 arm64 Release 生产应用纯构建。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug` | 52 个套件、266 项测试通过，沙盒内完整 U/I/L／隐私回归。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release` | 52 个套件、266 项测试通过，Release Swift `-O`／整模块优化与对应产物；不是仅优化 Rust 内核。 |
| 构建脚本参数探针（替换 `xcodebuild` 为只检查参数的合成接收器） | 改前请求 Release 实际传 Debug，退出 1；改后实际传 Release，退出 0。探针未调用 Xcode，不是生产构建证据。 |
| `rtk proxy bash -n script/build.sh script/test-isolated.sh` | 通过。 |
| `rtk proxy ./script/test-isolated.sh --configuration invalid` | 按预期在构建前退出 2。 |

初始环境曾因 Xcode 许可退出 69，未执行测试；用户接受当前协议后继续。Swift 6.4 编译暴露默认 MainActor 协议及跨文件 actor 推导问题，按[隐私契约](daily-report-privacy.md)明确外部协议并在替身扩展中声明遵守；隔离脚本改用当前 swiftbuild 的测试包。首次 Release 隔离构建缺少 `@testable` 可见性而失败，加入仅隔离构建的 `-enable-testing` 后完整通过。这些编译失败均不当作行为红绿证据。

两次生产构建没有 Swift 编译警告；Xcode 输出 CoreDevice 插件缺失符号、CoreSimulator 组件版本落后的环境诊断，以及既有的 AppIntents 元数据跳过提示，macOS 目标均完成构建。未为处理这些诊断安装组件或修改系统配置。

code-review 固定起点为 `a62e7ec`，按用户要求先评审后提交，由两个独立代理分别检查本票暂存差异，排除工程文件无关变化。Standards 初审纠正剪贴板保留的文档分类；Spec 初审纠正单份删除应保留确认快照的测试断言，清空全部内容才删除所有快照。修正后双配置完整隔离回归通过；代码复核为 Standards 0 项规范违反／可行动气味、Spec 0 项缺失／实现错误／范围扩张。

清理了旧通用生成日志 format 和旧 SwiftPM 测试包路径假设；未删除完整产品文件、数据库或用户数据，没有新增迁移、兼容入口、生成档案、自动备份或重试。

未执行应用启动、旧生产宿主／UI 测试、真实 Codex／AI、用户数据库操作、OSLog 实际落盘检查、macOS 26.5 人工验收、真实组合语义或性能验收。#35／#36 的人工／系统／真实机制验收仍未完成；本记录不声明整个父规格验收通过。

## 命令

在仓库根目录运行：

```bash
./script/build.sh --configuration Debug
./script/build.sh --configuration Release
./script/test-isolated.sh --configuration Debug
./script/test-isolated.sh --configuration Release
./script/test-isolated.sh --filter IntelligenceIsolationTests
```

`build.sh` 仅调用 Xcode 的 `build`，产物位于 `.build/DerivedData`，不运行旧启动脚本，也不终止已运行的应用。隔离入口先用 SwiftPM 的 `swiftbuild` 构建系统编译测试，并加载它生成的 `IsolatedTests.xctest`，再在 macOS 沙盒内执行 Swift Testing 测试程序；默认 Debug；`--configuration Debug|Release` 同时选择 Swift 编译和测试产物，支持 Swift Testing 的 `--filter` 参数。隔离构建显式传 `-enable-testing` 以供现有 `@testable` 接口使用，Release 仍使用 `-O`／整模块优化；该选项不进入生产应用纯构建。它没有应用可执行产品、生产 `TEST_HOST` 或生产入口初始化。

macOS 的 `.xctest` 是加载包，脚本用当前工具链的 `swiftpm-testing-helper` 加载它，调用方式依据 [Swift Testing 官方说明](https://github.com/swiftlang/swift-testing/blob/main/Documentation/CommandlineDebugging.md)。沙盒只允许执行该加载器、#23 的 `ReportStorageProbe` 和 #25 的 `SyntheticCodexServer`。两个替身仅接收本次临时根目录内的合成数据库或协议夹具，用于真实 SQLite／stdio 机制验证，不是应用或 Codex 入口。stdio stderr 丢弃到 `/dev/null`，沙盒仅为此放行该空设备，其他文件写入仍限于临时根目录。

旧 Xcode 测试目标仍包含真实窗口聚焦等系统测试，必须单独获得应用启动授权：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -scheme random-thoughts \
  -destination 'platform=macOS' test
```

此命令会启动应用及 UI 测试，不能用作隔离验证。`build_and_run.sh` 的各模式同样属于应用启动操作。

## 复用实现与外部边界

SwiftPM 的 `random_thoughts` 库直接编译清单列出的生产 Swift 文件，Xcode 应用继续编译这些文件，业务实现不复制。清单只纳入可隔离实现；生产 `@main`、应用 Delegate、AppKit 窗口操作、蓝牙及系统操作 Adapter 不在测试产物中。`DailyReportFlow` 的动作／状态接口供日报界面和主要业务测试共用；窗口系统动作注入受控接收器，原生内容通过 `NSHostingView` 测量且不创建窗口。#23 接入内存草稿与真实 SQLite，#26 接入候选扫描、选择与内存快照，#27 接入三协议配置、真实 CryptoKit 和凭据事务，#28 接入 Chat Completions 显式探测、离线预算与直接生成。各边界详见 [daily-report-windows.md](daily-report-windows.md)、[daily-report-content.md](daily-report-content.md)、[codex-session-scan.md](codex-session-scan.md)、[ai-service-settings.md](ai-service-settings.md) 与 [chat-completions-generation.md](chat-completions-generation.md)。

模型刷新作为既有行为的验证样本：Store 显式接收服务、UserDefaults、时钟和调度，服务显式接收 URLSession。只有生产组合传入真实会话及系统时间，测试组合使用合成传输和受控时间。构造 Store 不启动刷新；受控调度用明确屏障推进，失败保留旧状态且不改用生产依赖。

## 运行环境及隔离证据

- 每次运行建立独立临时根目录；每个测试环境再分配独立目录、数据库位置、合成测试密钥和随机 UserDefaults suite。`defer` 清理 suite 与目录，脚本退出再清理整次运行目录；不删除或重置用户数据库。
- 固定时钟与可控调度器可供后续日报模块注入。用完成/调度屏障等待，不通过任意 sleep、真实聚焦、用户凭据或 Codex 数据建立前提。
- 数据库重开测试先等待 `DailyReportDatabase.close()` 归还连接与目录锁，不依赖异步任务中 ARC 临时引用的释放时机；生产组合仍持有应用生命周期内的唯一连接。
- 合成 URLProtocol 仅安装到测试专用的 ephemeral URLSession，禁缓存/凭据/Cookie 存储。未知请求或注入故障直接失败，不回退 `URLSession.shared`。
- 执行沙盒仅开放脚本选定的一个回环 HTTP 端口，供测试进程内的串行假服务使用；禁止其余网络、未列入白名单的进程执行、蓝牙服务访问以及真实用户主目录内容读取。主目录内仅放行仓库读取，系统框架正常读取。所有文件及偏好写入独立临时位置。脚本要求系统沙盒可用，任何准备或沙盒失败均非零退出，不提供无隔离重跑分支。
- U 验证既有刷新状态与固定时间；I 验证真实请求构造/解码、受控失败和沙盒禁止能力；L 通过 `NSHostingView.fittingSize` 测量生产卡片，不创建、展示或聚焦窗口。

日报遥测测试直接使用固定版本 CocoaLumberjack，在独立 `DDLog` 中注册线程安全内存 logger；生产者完成提交后在日志队列外 `flushLog()`，检查完整 `DDLogMessage` 及最终文本。生产注册测试检查唯一 `DDOSLogger` 与无 formatter，固定 subsystem/category 由源码核对，不发系统日志事件。真实聚焦、Dock、快捷键与睡眠／唤醒交互由授权的 #35 验收承接。

这一入口不代表全部 SQLite/CryptoKit 契约、tokenizer、真实 Codex/AI、系统交互或整个日报功能已经验收。#23／#24 已验证各自使用的真实 SQLite 机制；后续各票继续补充其机制和行为测试，并记录实际执行的命令、结果及未执行项目。

## #21 验证记录（2026-10-09）

实际环境：Apple Silicon、macOS 26.6（25G72）、Xcode 26.6（17F113）、Swift 6.3.3。测试构建要求 Swift 6.3，生产最低系统版本仍为 macOS 26.5。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`；仅生产应用目标，无签名、启动或终止操作。 |
| `rtk proxy ./script/test-isolated.sh` | 3 个 suite、11 项测试通过，其中一项包含 2 个参数用例。 |
| `rtk proxy bash -n script/build.sh script/test-isolated.sh` | 通过。 |
| `rtk git diff --check` | 通过。 |

所有旧测试调用方另外只编译、不执行，结果为 `BUILD SUCCEEDED`：

```bash
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -target random-thoughtsTests \
  -configuration Debug -sdk macosx -arch arm64 CODE_SIGNING_ALLOWED=NO \
  SYMROOT=.build/legacy-test-build OBJROOT=.build/legacy-test-build/Intermediates build
```

生产构建有 Xcode 的“未依赖 AppIntents，跳过元数据提取”提示；旧宿主测试编译另有 4 条来自未修改的 `ProximityLockTests` 的 MainActor/Equatable 警告。本票的隔离目标编译无警告，未借 #21 修改其他蓝牙测试。

| 层级 | 测试 / 证据 | 结果 |
| --- | --- | --- |
| U | `refreshUsesFixedClockWithoutStartingInInitializer` | 构造无请求，显式刷新使用固定时间并产生合成状态。 |
| U | `automaticRefreshOnlyContinuesWhenControlledTimeAdvances` | 重复启动不重复调度；只有推进到 1,800 秒并通过调度屏障才进行第二次刷新。 |
| I | `fetchUsesInjectedTransport` | 真实服务构造请求并解码合成响应，目标/Accept/请求数符合预期。 |
| I | `transportFailureKeepsCachedContentAndDoesNotRetry` | 故障保留旧正文数据和时间，不重试或切换传输。 |
| I | `rejectsMalformedDataAndUnsuccessfulResponses` | 非法 JSON 与 HTTP 503 各一次即失败，无生产 fallback。 |
| I | `deniesReadingProductionUserDirectories` / `deniesUncontrolledNetworkConnections` | 用户 Codex 目录打开、非受控本机连接均返回 `EPERM`，未读取内容或建立连接。 |
| I | `deniesUncontrolledSubprocesses` / `deniesBluetoothServiceLookup` | POSIX `posix_spawn` 无害探针返回 `EPERM`；蓝牙服务 lookup 返回 `BOOTSTRAP_NOT_PRIVILEGED`，不取得服务端口。 |
| U/I | `keepsTemporaryStorageAndPreferencesIndependent` | 独立目录、测试数据库位置/密钥及 suite 可用；清理后目录与偏好消失。仅验证测试存储位置，不代表 SQLite 已实现。 |
| L | `metricCardFitsWithoutCreatingAWindow` | 生产卡片为 260×88pt，`window == nil`。 |

核对 SwiftPM 生成的源文件清单：只有模型、服务、Store、既有遥测和卡片五个生产文件，没有应用入口、生命周期或蓝牙 Adapter。测试包直接链接 Foundation/SwiftUI/Testing，没有生产应用或 CoreBluetooth 链接依赖；真实用户目录内容受沙盒阻止，偏好使用临时 `CFFIXED_USER_HOME`，并禁止连接用户 `cfprefsd` agent。

测试先后暴露并修复了缺少可注入传输、固定时钟/调度、停止更新入口及重复清理问题，保留了对应回归。未启动生产应用、运行旧宿主/UI 测试或调用真实 Codex/AI；未执行父规格的真实机制、语义、系统交互或性能验收，这些不属于 #21 的已验证结果。

## #22 验证记录（2026-10-10）

本票复用 #21 的 macOS 26.6、Xcode 26.6、Swift 6.3.3 环境。SwiftPM 与 Xcode 均解析 CocoaLumberjack 3.10.0（`b75d3c3198a2930b4491b04fd47cb504b359c750`），两个 `Package.resolved` 同时固定上游清单声明的 swift-log 1.16.1；应用只链接 CocoaLumberjack 产品，不接入 swift-log 后端。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 Debug 纯构建。 |
| `rtk proxy ./script/test-isolated.sh` | 8 个 suite、22 项测试通过，其中原有一项包含 2 个参数用例；新增 11 项测试。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportWindowTests` | 5 项窗口流程状态测试通过。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportLayoutTests` | 2 项原生内容尺寸测试通过，无 NSWindow。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportTelemetryTests` | 2 项真实 CocoaLumberjack 内存捕获／注册测试通过。 |
| `rtk proxy ./script/test-isolated.sh --filter AppLaunchTests` | 1 项合成 Apple Event 启动原因测试通过。 |
| `rtk git diff --check` | 通过。 |

旧宿主与 UI 测试调用方只编译，结果为 `TEST BUILD SUCCEEDED`，没有执行测试或启动应用：

```bash
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -scheme random-thoughts \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

| 层级 | 新增测试 | 验证行为 |
| --- | --- | --- |
| U | `userLaunchOpensReportWhileLoginLaunchKeepsMenuBar` | 主动／登录启动分别打开日报或保持菜单栏。 |
| U | `repeatedOpeningAndReactivationReuseBothWindows` | 设置独立、仅设置存在时再次打开增加日报；重复打开保持各自实例身份。 |
| U | `onlyActualClosingOfTheLastWindowReturnsToMenuBar` | 隐藏／最小化／睡眠／唤醒不删除窗口；最后一个真实关闭后切回菜单栏。 |
| U | `oldCloseCallbackCannotCloseAReopenedReport` | 旧实例关闭回调不影响新实例。 |
| U | `reportDateNavigationAndHistoryResetOnlyOnActualReopening` | 单日期导航、历史折叠保留到真正关闭，再次打开回到今天与展开历史。 |
| U | `recognizesLoginLaunchOnlyFromTheOpenApplicationEvent` | 使用合成公开事件识别登录启动，普通打开及再次打开不会误分类。 |
| U | `menuOffersSpecifiedShortcutsAndOnlyMinimizesTheReport` | 原生菜单配置包含五个规定快捷键，无 ⌘N；设置／无窗口时禁用日报最小化。未安装系统菜单或触发系统动作。 |
| L | `reportFitsDefaultAndMinimumSizesWithoutAWindow` | 生产 SwiftUI 内容默认 1100×760pt，最小 900×620pt，折叠历史后仍满足最小尺寸。 |
| L | `settingsKeepFixedSizeForExistingAndDailyReportRoutes` | 三个设置入口的原生内容为 860×620pt；窗口配置禁止设置最小化／调整／全屏。 |
| I | `capturesOnlyWindowModesAndFixedMetadata` | 独立日志实例经 flush 捕获两个允许模式，消息、格式、file/function、line/context、representedObject 及 formatter 都符合白名单。 |
| I | `productionRegistersOnlyTheSystemLoggerWithoutFormatter` | 生产注册器只包含 DDOSLogger，无 formatter；固定 subsystem/category 另由源码核对。未写系统日志事件。 |

文档先于测试／实现更新。启动、单例、关闭、日期、布局和日志切片的首轮测试均先因缺少相应生产接口或依赖失败，再加入最小实现并通过；失败输出已逐项检查。隔离目标最终编译无警告。生产构建只有既有的 AppIntents 元数据跳过提示；旧测试编译仍有未修改的 `ProximityLockTests` 中 4 条 MainActor／Equatable 警告，本票未扩展到蓝牙测试整治。

删除了 `SettingsWindowPresenter.swift` 的标题猜测／延时聚焦、仅它使用的旧 Windowing logger、对应的真实窗口聚焦测试，以及蓝牙 Store 的两处激活策略写入；模型设置内容移至独立视图，所有调用方一起更新。`setActivationPolicy` 只剩窗口协调器一处。

code-review 首轮 Standards 提出 1 项 P2：`SettingsView` 留有旧日期格式化转发入口。按不做向后兼容的仓库规则，删除该入口，并将唯一测试调用方直接更新为 `IntelligenceSettingsView`。两轴各自复核最终修订后，Standards 为 0 项未解决问题、0 项新增可行动气味；Spec 为 0 项问题。

未执行：生产应用启动、真实聚焦／反最小化／Dock／快捷键／系统睡眠唤醒、截图、macOS 26.5 人工验收、旧宿主／UI 测试执行、真实 Codex／AI、OSLog 持久化／采样。真实窗口系统交互按 #22 分工由 #35 承接，窗口正常尺寸持久化由 #23 承接；本票结果不代表完整日报交付验收。

## #23 验证记录（2026-10-11）

本票沿用 #22 的 macOS 26.6、Xcode 26.6、Swift 6.3.3 环境。实现边界见 [daily-report-content.md](daily-report-content.md)。只处理手写、保存、历史、内存草稿保护与正常窗口尺寸，没有扫描、AI、配置编辑、迁移或重置。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，修订后的生产 Debug 纯构建。 |
| `rtk proxy ./script/test-isolated.sh` | 12 个 suite、42 项测试通过；存储故障含 9 个参数用例、DST 含 4 个参数用例、退出尺寸屏障含 2 个参数用例。 |
| `rtk proxy bash -n script/build.sh script/test-isolated.sh` | 通过。 |
| `rtk git diff --check` | 通过。 |

旧宿主及 UI 测试调用方使用 #22 记录的 scheme `build-for-testing` 命令，只编译而不执行，结果为 `TEST BUILD SUCCEEDED`。先前单独编译旧测试 target 因未构建 Swift Package 依赖而缺少 CocoaLumberjack module map；改用 scheme 后通过。隔离目标没有编译警告；生产构建仅既有 AppIntents 元数据跳过提示，首次旧测试编译观察到未修改的 `ProximityLockTests` 中 4 条 MainActor／Equatable 警告。

| 层级 | 新增或扩展的验证 | 结果 |
| --- | --- | --- |
| U | 手写、删空、空正文、相同正文、精确撤销、原样复制与保存时间 | 首次有效编辑建立草稿，既有正文精确撤销清草稿；显式保存允许空／相同正文，不附来源或改写 Markdown。 |
| U | 覆盖确认竞争、保存失败与提交屏障 | 旧确认不能保存变化后的正文；失败保留原文和草稿，本地重试成功才清草稿；提交期间不能改正文或结束。 |
| U | 跨日期／时区关闭与退出保护、旧回调／旧确认 | 默认取消后保留全部草稿；逐份保存或确认放弃才结束，真关闭不恢复草稿或确认面板；返回编辑取消待执行的退出，撤销正文后旧任务也不能退出；确认结束后的迟到取消不能阻止已确认退出。 |
| U | 报告日与正常尺寸 | New York 的 23／25 小时及 Havana、São Paulo 跳过午夜均取正确日边界；受控写入期间尺寸 A→B→A 最终恢复 A，尺寸限制符合主显示区域约束；直接退出或确认放弃后退出都等待最终尺寸提交，等待期间新建草稿仍须确认。 |
| U | 原始 unified diff 与安全预览 | 保留空格、Unicode 差异和末行换行状态；预览保留段落／列表及行内格式，只保留允许显式打开的链接。 |
| I | 真实 SQLite、独立进程锁及存储故障 | 原文与尺寸经真实 SQL 读取，目录／文件权限为 0700／0600；第二进程被拒绝，持锁者结束后可打开；真实提交失败回滚并可重试。 |
| I | 坏字段／schema／版本／权限、恢复或重置标记 | 专用子进程拒绝处理且主库字节不变；缺少报告日主键并含重复记录的库也被拒绝；主库缺失但有恢复标记时不创建。 |
| L | 最小／默认尺寸、长正文、预览和确认 | 生产内容经无窗口 `NSHostingView` 测量通过；没有创建 `NSWindow` 或呈现 sheet。 |

文档先更新，再通过隔离测试确认失败并完成实现。code-review 首轮 Standards 提出 1 项 P2（缺少主键校验），Spec 提出 3 项 P2（预览段落合并、午夜 DST 日边界、异步尺寸去重），Spec 复审另提出 2 项 P2（尺寸写入未完成时允许退出、返回编辑未取消等待退出）；均新增或扩展回归，先确认失败再修复。另补关闭后的旧确认清理和确认结束后的迟到取消回归。最终两轴独立复核：Standards 为 0 项未解决问题、0 项新增可行动气味，Spec 为 0 项未解决问题。

删除了日报正文旧占位内容及流程旧初始化方式，所有生产、隔离和旧宿主测试调用方一起更新；没有保留兼容入口，也没有删除数据库、用户数据或完整源文件。

未执行：生产应用启动、旧宿主／UI 测试执行、真实窗口／sheet 调整与滚动／聚焦／主显示器居中／全屏／最小化等系统交互、截图、macOS 26.5 人工验收、真实 Codex／AI、OSLog 持久化及父规格性能验收。这些结果不代表整套日报功能或系统交互已验收。

## #24 验证记录（2026-10-11）

本票沿用 #23 的 macOS 26.6、Xcode 26.6、Swift 6.3.3 环境。实现范围见 [daily-report-settings.md](daily-report-settings.md)。仅开放常规设置，取消／重扫由类型化受控 Adapter 验证，不接入数据源或生成协议。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 Debug 纯构建。 |
| `rtk proxy ./script/test-isolated.sh` | 13 个 suite、60 项测试通过；新增 14 项设置流程、3 项存储、1 项布局测试，设置离页／退出／回看／存储故障／提交与时区竞争包含参数用例。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportSettingsTests` | 14 项设置流程测试通过；有效 IANA 名含 11 个参数，非法名含 5 个参数，正文与设置提交期间通知含 2／4 个参数。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportDatabaseTests` | 6 项真实存储测试通过，新增设置故障含 6 个参数用例、有效时区日报保存重开含 8 个参数用例。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportLayoutTests` | 4 项无窗口原生布局测试通过。 |
| `rtk git diff --check` | 通过。 |

| 层级 | 验证行为 | 证据 |
| --- | --- | --- |
| U | 独立设置加载、统一保存／撤销、语言／偏好／0–7 回看、越界输入拒绝 | `generalSettingsCommitTogetherAndRevertToSavedValues`、`invalidHistoryLookbackIsRejectedWithoutSavingOtherEdits`。 |
| U | 手动时区确认、多个旧日期、目标时区草稿与全部已保存日报保留、提交冻结、失败原子保护 | `manualTimeZoneChangeCommitsBeforeDiscardingAllOldDatesAndKeepsTargetDrafts`。 |
| U | 自动时区清旧草稿、事后计数、取消／重扫、重复通知、旧编辑代次拒绝 | `automaticMacTimeZoneChangeClearsOldDatesAndRejectsLateEditsWithoutConfirmation`。 |
| U | 正文／设置提交期间合并最新时区通知，成功／失败返回后串行切换、保留目标草稿，排除删除后迟到保存 | `automaticTimeZoneChangeWaitsForReportCommitBeforeClearingOldDrafts`、`automaticTimeZoneChangeWaitsForSettingsCommitAndRetainsItsTargetDrafts`。 |
| U | 有效 `Etc/GMT` 与无斜杠 IANA 名可选择保存重开；非 IANA 偏移字符串、未知名及尾空格拒绝 | `validFixedIanaZonesCanBeSelectedSavedAndReopened`、`invalidFixedIanaNamesRemainUnchangedAndCannotBeSaved`。 |
| U | 无效已保存固定值保留及修复、模式变化不等于有效时区变化、不改变已有生成设置值副本 | `invalidSavedFixedTimeZoneRemainsUnchangedAndBlocksNewInputsUntilRepaired`、`changingOnlyTheModeRetainsDraftsAndNonTimeZoneSettingsOnlyAffectNewGenerationValues`。 |
| U | 同一离页／关闭／退出保护、取消不提交、放弃设置不删日报、失败留页、旧窗口及确认失效 | `leavingGeneralSettingsCombinesSaveAndDraftImpactAndFailureKeepsThePage`、`closingSettingsCanCancelDiscardOrSaveWithoutClosingTheReport`、`quitCombinesUnsavedSettingsAndAllReportDraftsWithCancellationAsTheDefault`、`confirmationKeepsItsIntentWhileDraftsAndAutomaticTimeZonesChange`。 |
| I | SQLite 设置真事务、提交失败回滚、释放锁后重试、重新打开与 UTF-8 原值 | `sqliteCommitsGeneralSettingsTogetherAndRollsBackRealCommitFailure`；用独立合成库的真实读锁阻止 COMMIT，不模拟 SQLite 的结果。 |
| I | 有效固定时区与其日报正文共用校验，存储关闭重开后保持原日期／时区身份 | `validFixedIanaSettingsAndReportsReopenWithTheirOriginalIdentity`。 |
| I | 旧 schema、坏设置模式／语言／回看、缺设置行拒绝，失效固定时区保持原值 | `savedSettingsFaultsPreserveTheOriginalDatabase`；专用测试进程核对原库字节不变，无自动迁移／重置。 |
| L | 常规页长偏好与统一保护面板适配固定设置尺寸，无 NSWindow | `generalSettingsAndMergedConfirmationFitWithoutAWindow` 与既有路线尺寸测试。 |

文档先更新，接口缺失与离页／日期竞争行为的测试先失败，再完成最小实现；失败输出均已检查。隔离目标编译无警告，生产构建只含既有 AppIntents 元数据跳过提示。危险确认的默认取消和各具体控件的指针样式由源码评审核对，不冒称系统键盘交互已验。

旧宿主和 UI 测试调用方另用 #22 记录的 scheme `build-for-testing` 命令只编译，结果为 `TEST BUILD SUCCEEDED`，没有执行或启动应用。输出包含未修改的 `ProximityLockTests` 中 4 条 MainActor／Equatable 警告、AppIntents 元数据跳过提示，以及 Xcode 解析打包 XCTestCore／Testing 框架时的 2 条工具提示；本票没有扩展到这些蓝牙测试或测试框架处理。

code-review 固定起点为本票开始时的 `27b065e4b9a9fa0afd6596de804272c7fe0e1499`，提交前评审暂存差异，不含此前 10 个未推送提交。Standards 首轮提出 1 项 P3（未使用确认字段），已删除；Spec 首轮提出 2 项 P2（提交期间自动时区变化后迟到保存、有效 IANA 时区被候选表误拒绝），均补失败回归后修复，另以真实 SQLite 回归发现并统一报告日读取校验。失败提示只陈述本次保存保证，避免与独立自动时区清除说明矛盾。最终独立复核：Standards 为 0 项硬性违反、0 项新增可行动气味；Spec 为 0 项未解决问题、0 项新增问题、0 项范围扩张。Spec 复核另运行 `rtk proxy ./script/test-isolated.sh --filter 'DailyReportSettingsTests|DailyReportDatabaseTests'`，2 个 suite、20 项通过；最终全套 60 项及生产纯构建也已亲自检查输出。

删除了常规设置占位内容、视图自行维护的设置选择状态及评审发现的未使用确认字段；所有流程、视图、隔离和旧宿主测试调用方一起更新。正文编辑接口增加时区变化代次，没有保留兼容入口。没有删除用户数据库、数据或完整源文件；schema 2 拒绝旧 schema 并保留原库，本票不迁移。

未执行：生产应用启动、旧宿主／UI 测试执行、真实设置窗口／sheet／键盘／滚动／系统时区通知与睡眠唤醒交互、截图、macOS 26.5 人工验收、真实 Codex／AI、历史输入规划、OSLog 持久化及父规格性能／语义验收。取消／重扫与设置值固定的受控验证不代表真实任务或系统交互已经验收。

## #25 验证记录（2026-10-11）

沿用 #24 的 macOS 26.6、Xcode 26.6、Swift 6.3.3 环境。范围见 [codex-data-source.md](codex-data-source.md)。#23 的本地实现为 `27b065e`，GitHub 仍开放；开始时现场重跑其内容及真实数据库测试，2 个 suite、17 项通过。本票已认领，仅新增来源设置与操作级基础检查，扫描、候选和生成留给后续票。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`；仅生产 Debug 构建。 |
| `rtk proxy ./script/test-isolated.sh` | 16 个 suite、78 项测试通过；比 #24 新增 18 项，参数用例另计。 |
| `rtk proxy ./script/test-isolated.sh --filter 'CodexDataSourceTests\|CodexStdioTests'` | 2 个 suite、11 项通过；其中流程 7 项覆盖保存、重启、失败、旧回调、离页和退出。 |
| `rtk proxy ./script/test-isolated.sh --filter CodexSourceDiscoveryTests` | 3 项通过；四级发现、稳定入口、目录优先级及路径／权限拒绝。 |
| `rtk proxy ./script/test-isolated.sh --filter 'CodexStdioTests\|sourceAndDiagnosticsCommit\|sourceStorageFaults'` | 真实机制联测通过；stdio 成功含 7 个场景，协议故障含 9 个场景，存储损坏含 6 个场景。 |

旧宿主和 UI 测试调用方另用 #22 记录的 scheme `build-for-testing` 命令只编译，结果为 `TEST BUILD SUCCEEDED`，未执行测试或启动应用。隔离编译无警告；生产纯构建仅既有 AppIntents 元数据跳过提示。首次旧测试编译另有未修改的 `ProximityLockTests` 中 4 条 MainActor／Equatable 警告，以及 Xcode 解析打包 XCTest／Testing 框架时的 4 条工具提示；最终增量编译仅余 AppIntents 提示。

| 层级 | 验证行为 | 证据 |
| --- | --- | --- |
| U | 同库保存后才检查、失败保留新来源、存储失败保留旧来源与编辑、不取消旧检查 | `aFailedCheckKeepsTheCommittedSourceAndExistingReportAndDraft`、`storageFailureDoesNotCancelTheOldCheckOrReplaceItsCommittedSource`。 |
| U | 自动结果仍为自动模式、持久历史与当前状态分开，重启不启动检查 | `savingAndCheckingKeepsAutomaticIdentityButRestartIsUnchecked`。 |
| U | 新来源取消旧检查、隔离迟到结果与诊断、快照上下文通知不影响草稿和日报 | `replacingSourceRejectsLateDiagnosticsAndKeepsOnlyTheNewIdentity`，上下文 effect 使用来源代次，扫描 Adapter 尚未接入。 |
| U | 同一离页／关闭保护、失败留页、旧确认失效、返回编辑继续检查，实际关闭／退出取消 | `leavingEditedSourceUsesOneConfirmationAndStorageFailureKeepsThePage`、`cancelledLeaveConfirmationKeepsCheckingButActualCloseRejectsLateSuccess`、`quittingCancelsTheCurrentCheckAndRejectsItsLateResult`。 |
| I | 真实文件检查及规范化单目录；无效显式／继承值不回退，不创建 Codex 目录 | `CodexSourceDiscoveryTests`；发现入口为专用替身的稳定符号链接，未执行其他文件。 |
| I | 真实管道握手、当前／归档稳定列表和 includeTurns 读取；通知、未知内容、9 MiB 响应、旧或未解析版本 | `realStdioChecksStableMethodsWithoutStartingOrResumingAThread`；替身严格核对方法与参数，空列表不制造会话，版本不作能力门槛。 |
| I | 方法／参数／必要 schema、握手／读取、非法响应、传输中断、截止时间与取消 | `protocolFailuresExposeOnlyFixedErrorsAndReapTheOperation`、`cancellingABlockedRealPipeReturnsWithoutLeavingTheChildRunning`；FIFO 为就绪屏障，不依赖任意 sleep；每次核对子进程已回收。 |
| I | SQLite 真提交失败回滚、成功保存重开、旧身份诊断不覆盖新配置、坏值／schema 拒绝且原库字节不变 | `sourceAndDiagnosticsCommitTogetherReopenAndIgnoreOldIdentity`、`sourceStorageFaultsRejectWithoutChangingTheOriginalDatabase`。 |
| I | 固定结果／错误码／数字版本进入真实日志对象，原始响应及 Error 不进入敏感出口 | `codexDiagnosticsOnlyLogFixedCodesAndParsedNumericVersions`；受限版本类型不接受原始文字，内存 logger 使用 `flushLog()`。 |
| L | 长入口／目录及诊断适配固定设置尺寸，无 NSWindow | `dataSourceEditorAndDiagnosticsFitTheFixedSettingsWindowWithoutAWindow`。 |

文档先更新，缺少来源接口、离页保护、stdio 和遥测入口的测试先失败，再完成实现。压力回归发现全缓冲反复扫描会使合法长响应超时，改为只扫描新增片段；基础管道读取改用可返回部分数据的 POSIX read，避免等待填满缓冲。协议替身场景串行验证，失败场景有独立截止时间。全套还发现重开测试依赖 ARC 释放时机导致偶发占用，改用显式连接关闭屏障，保留生产连接的生命周期目录锁。

code-review 固定起点为本票开始时的 `f88a832e3b11fbe82518fa49c46cf3e24ecb7a07`，提交前双轴独立评审暂存差异，不包含此前 11 个未推送提交。Standards 首轮提出 1 项 P3（入口错误分类重复），已统一为固定分类属性并复核；Spec 首轮为 0 项发现。最终 Standards 为 0 项硬性违反、0 项未解决气味、0 项新增问题；Spec 为 0 项缺失／错误、0 项范围扩张。分类重构后的 `rtk proxy ./script/test-isolated.sh --filter 'CodexDataSourceTests\|DailyReportTelemetryTests\|dataSourceEditorAndDiagnostics'` 为 3 个 suite、11 项通过。脚本 `bash -n` 与暂存差异 `git diff --cached --check` 均通过。

删除了数据源页占位分支和流程旧初始化签名，所有生产、隔离及旧宿主测试调用方一起更新；没有保留兼容入口、私有 JSONL 或常驻进程路径。未删除用户数据库、数据或完整源文件。schema 3 拒绝旧库并保留原文件，不迁移、不自动重建。

未执行：生产应用启动、旧宿主／UI 测试执行、真实文件选择／设置窗口／sheet／键盘／滚动与系统交互、截图、macOS 26.5 人工验收、真实 Codex／AI、会话扫描／生成、OSLog 持久化及父规格性能／语义验收。真实读取闭环由 #35 承接，当前替身检查不代表真实 Codex 已验收。

## #26 验证记录（2026-10-11）

起点为 `f36669b15306d04bf00eae477e8ae9c6619d0061`，工作区干净，当前分支已有 12 个未推送提交；本票只追加本地实现，不推送、不关闭 Issue。实时核对 GitHub #25 仍开放，#26 原生 `blocked_by` 仍指向 #25，远端 main 为 `123948d`；按用户指定的本地依赖继续，不把本地完成当远端解除阻塞。

实际环境：macOS 26.6（25G72）、Xcode 26.6（17F113）、Swift 6.3.3、Apple Silicon；生产最低版本仍为 26.5，没有增加外部依赖或改变 SQLite schema。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 Debug 纯构建。只有既有的 AppIntents 元数据跳过提示，没有新增 Swift 警告。 |
| `rtk proxy ./script/test-isolated.sh` | 首次 20 个 suite、98 项；评审修复后 20 个 suite、101 项测试通过，隔离目标编译无警告。 |
| `rtk proxy ./script/test-isolated.sh --filter CodexSessionFlowTests` | 初版 8 项动作／状态回归通过。 |
| `rtk proxy ./script/test-isolated.sh --filter 'CodexSessionWireTests\|CodexScanLockTests'` | 初版 2 个 suite、9 项测试通过；包含 9 个协议故障和 3 个锁等待结束参数用例。 |
| `rtk proxy ./script/test-isolated.sh --filter 'CodexSessionFlowTests\|CodexSessionWireTests'` | 评审修复后 2 个 suite、18 项通过，含新增正式用户来源、迟到检查和锁失败状态回归。 |
| `rtk proxy ./script/test-isolated.sh --filter CodexSessionPrivacyTests` | 真实 stdio → 流程 → 快照 → SQLite／偏好／日志对象隐私集成通过。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportTelemetryTests` | 4 项真实 CocoaLumberjack 对象捕获／注册测试通过，使用独立日志实例及 `flushLog()`。 |
| `rtk proxy ./script/test-isolated.sh --filter 'CodexSessionFlowTests\|DailyReportLayoutTests'` | 先验证 13 项（7 项流程、6 项布局），后来新增取消流程回归随全套通过；不创建 NSWindow。 |
| `rtk proxy git diff --check` | 通过。 |

旧宿主及 UI 调用方另外只编译，不执行或启动应用：

```bash
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -scheme random-thoughts \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

结果为 `TEST BUILD SUCCEEDED`。旧宿主编译仍有未修改的 `ProximityLockTests` 的 4 条 MainActor／Equatable 警告，以及本次 Xcode 解析打包测试框架的 2 条工具提示和 AppIntents 提示；没有执行旧宿主或 UI 测试。

| 层级 | 证据 | 验证行为 |
| --- | --- | --- |
| U | `scanningSelectsUserSessionsAndConfirmationFreezesTheInputWithoutReadingAgain`、`bulkAndGroupSelectionAskBeforeUnknownSourcesAndRefreshResetsTheirTrust` | 用户默认全选、未知默认不选，全选／分组／单会话经风险确认；刷新保留旧快照，重新确认才替换，不额外重读。 |
| U | `changingTheSelectionInvalidatesAnEarlierUnknownSourceApproval` | 改变选择后旧风险确认不能重新纳入会话。 |
| U | `scanningReplacesAnInFlightCheckAndRejectsItsLaterContradictoryResult`、`lockFailuresShowAScanErrorWithoutChangingSourceAvailability` | 扫描替代尚未完成的基础检查，迟到矛盾结果不能覆盖；两种锁失败保留未检查／可用能力状态，仅显示扫描错误。 |
| U | `savingANewSourceRejectsLateScansAndPreservesTheSnapshotDraftAndReport`、`actualCloseReleasesAllSourceMaterialAndRejectsTheOldWindowCallback`、`cancellingAScanKeepsSourceAvailabilityAndItsSnapshotAndShowsACancelledResult` | 来源代次、窗口结束、取消隔离旧扫描；快照／草稿／日报按规定保留或释放，不误报来源不可用。 |
| U | `confirmingMasksHighConfidenceCredentialsAndKeepsOrdinaryNamesAndPaths`、`redactionFailureStillConfirmsAndKeepsSuccessfulRedactionsInOtherFields` | 固定前遮盖鉴权值、Key 与私钥；保留自然路径／姓名／邮箱，遮盖失败可继续且保留其他字段的遮盖。 |
| I | `realWirePagesBothListsPrefersCurrentAndFiltersTurnsAtTheDSTBoundary`、`completeEmptyScanIsAvailableAndTheFallDSTDayIncludesBothRepeatedHours` | 两列表分页／ID 去重／当前优先、目录／worktree 分开、标题后备；23／25 小时日及午夜半开边界，无日期／未来内容排除，背景保留原日期与时区。 |
| I | `mixedWireKeepsOnlyOrderedTextAndFinalAnswersAndNeverReadsInternalSources` | 顺序 text、仅 final_answer、空用户正文排除；元数据、非文本、工具、reasoning、缺失／未知阶段排除，内部来源不可纳入。 |
| I | `explicitUserClassificationsKeepInteractiveSourcesSelectedWithoutTrustingUnknownSources`、合成 probe 的逐页参数检查 | 正式 `threadSource=user` 不误判已识别用户来源；未知来源自报 user 不升级信任，每页以空 modelProviders 避免默认供应商筛选。custom 合成项仅验证本地分类，固定上游列表不能返回该类型，范围限制见扫描契约。 |
| I | `aCompleteRangeAllowsOnlyReadableCandidatesToBeConfirmedAsAPartialScan`、`incompleteRangesAndUnsupportedContractsCannotBecomeSnapshotsOrRetryIndefinitely` | 部分成功显式列失败项；列表不全、全不可读、必要 schema／方法／参数／itemsView、循环游标均拒绝新快照；不把部分扫描当降级成功。 |
| I | `anInterruptedScanRestartsOnceAndReturnsOnlyTheCompleteSecondAttempt`、`cancellingARealScanReapsItsChildAndDoesNotRestartIt` | 仅传输／超时整次至多一次重启，取消不重启且回收自己的子进程。 |
| I | `anotherProcessSerializesTheSameSourceAndWaitingCanEndWithoutStartingAChild`、`aDifferentSourceDoesNotQueueBehindAnotherProcess` | 使用生产 flock 的独立进程持锁；同源等待／取消／截止不抢锁，不启动第二个子进程；不同身份独立。FIFO／stdin 屏障，无任意测试 sleep。 |
| I | `realWireThroughTheFlowKeepsSnapshotsOutOfSQLitePreferencesAndLogObjects`、`scanTelemetryContainsOnlyOutcomesAndAggregateCounts` | 真实 wire 经统一流程，扫描材料不入库／偏好／日志对象；只保存用户明确正文，遥测只含固定结果和聚合数量，关闭不恢复或隐式重扫。 |
| L | `sourceDrawerAndLongSessionListsFitTheMinimumReportWithoutAWindow` | 长标题／多目录抽屉、历史展开／折叠在 900×620 内适配，正文与底部操作保留空间，无 NSWindow。 |

文档先更新，流程／wire／锁／遮盖／布局／遥测接口缺失先红再实现；旧未知来源确认与取消结果的行为回归也先观察失败再修复。旧专用 `CodexStdioCheck.swift` 替换为共用 `CodexStdioSession.swift`，所有生产、隔离及旧宿主调用方一起更新，没有兼容入口、私有 JSONL 或常驻子进程。未删除或重置用户数据库与数据。

code-review 固定起点为 `f36669b15306d04bf00eae477e8ae9c6619d0061`，提交前双轴独立评审本次暂存差异，不包含此前 12 个未推送提交。Standards 初审与复核均为 0 项硬性违反、0 项可行动气味。Spec 初审发现 1 项 P1 和 3 项 P2：默认供应商过滤漏会话、正式 user 来源误判、旧基础检查覆盖扫描结果、锁失败误报来源不可用；各项均先观察回归失败再修复，复核为 0 项未解决问题、0 项新增缺失／错误／范围扩张。修复后的相关 18 项与全套 101 项均通过，生产纯构建再次为 `BUILD SUCCEEDED`；固定上游 custom 范围限制已记录，没有扩展读取路径。

未执行：生产应用启动、旧宿主／UI 测试执行、原生窗口／抽屉／sheet 的实际点击、键盘、滚动、聚焦与系统交互、截图、macOS 26.5 人工验收、真实 Codex／AI、OSLog 落盘、父规格的性能与语义验收。真实 Codex 读取闭环仍由 #35 承接，隔离 wire 不代表真实 Codex 已验收。
## #27 三协议配置与凭据验证记录

2026-10-12，本地 `c43f0d2` 上只实现 #27。#23 的本地 `27b065e` 已在基线中；先运行 `rtk proxy ./script/test-isolated.sh --filter 'DailyReportContentTests|DailyReportDatabaseTests'`，2 个套件、19 个测试通过。GitHub #23 仍开放并被 #22 阻塞，#27 仍被 #23 阻塞；本次不推送或关闭 Issue。

文档、测试、实现按顺序进行：先观察新增流程／加密／布局测试因缺少对应生产接口失败；日志集成测试明确因缺少四条固定存储事件失败，再补最小实现。专用存储探针的七类 AI 坏库场景先失败，再接入真实数据库读取检查；没有用重建空库让测试通过。

验证入口与行为：

- `AIServiceSettingsTests`：三份隔离配置、不完整保存、完整路由与 HTTP 提示、原生默认值和预算范围、精确校验基线、C／并发保留资格、请求字段改变失效但保留当前身份；设置离开保护、编辑／窗口／确认过期、加密与提交失败、主动显示／复制的晚到解密结果、独立删除确认及回滚。新增切页往返投递旧确认／编辑，以及 Unicode 规范等价但请求字节不同的模型编辑／资格回归。
- `AICredentialTests`：真实 AES.GCM 的随机 nonce、完整 Unicode／NUL 明文往返、独立实例共享测试密钥；封装／密钥版本、认证标签与短密文错误，不修改原封装。
- `AIServicePersistenceTests`：真实 SQLite 读事务锁导致 COMMIT 失败，配置／密文／逻辑版本／校验证据完整回滚；删除失败保留原值、重试与重开成功；三份配置、当前身份及日报共存，坏密文仅阻断对应配置。旧 schema、缺行、未知协议、坏 JSON／预算／列结构／选择行在专用隔离子进程中拒绝并保持原库字节。
- `AIServicePrivacyTests`：真实 CryptoKit／SQLite 经过 `DailyReportFlow.send`；凭据明文不进入数据库或偏好，主动复制精确返回已保存值；生产者完成后用独立 DDLog 的 `flushLog` 屏障捕获整个日志对象，只含固定操作／结果／版本，不含端点、模型、Key、密文、内置测试密钥或现场元数据。
- `DailyReportLayoutTests.allNativeAIEditorsAndCredentialConfirmationFitWithoutAWindow`：三种原生编辑器、长路由／模型及编辑保护确认在无 NSWindow 的 NSHostingView 中布局。字段错误由流程固定枚举保留，界面映射到对应字段与 FocusState；实际键盘和系统焦点交互未执行。

AI 传输由 #28 后续接入，本切片不创建网络客户端。启动／保存／切类型只走本地存储与加密，无 AI 请求入口；流程测试确认 Codex 检查和扫描调用均为 0。全量隔离测试同时验证沙盒拒绝真实网络、用户目录、蓝牙和未受控子进程。

实际结果：

- `rtk proxy ./script/test-isolated.sh --filter 'AIService|AICredential|DailyReportTelemetryTests|DailyReportLayoutTests'`：6 个套件、28 个测试通过。
- `rtk proxy ./script/test-isolated.sh`：初版 24 个套件、119 个测试通过；评审修复后的最终全套为 24 个套件、121 个测试通过。
- `rtk proxy ./script/build.sh`：`BUILD SUCCEEDED`，只构建生产应用。保留工具已有的 AppIntents 元数据缺少依赖提示；未新增 Swift 编译警告。
- `rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project random-thoughts.xcodeproj -scheme random-thoughts -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing`：`TEST BUILD SUCCEEDED`，旧宿主与 UI 调用方仅编译。仍有未修改的 `ProximityLockTests` 的 4 条 MainActor／Equatable 警告及 AppIntents 工具提示，没有执行这些测试。

清理了 AI 服务页占位分支、旧流程初始化签名；全部生产、隔离及旧宿主调用方一起更新。共享存储探针调用移入测试 Support，删除原私有重复入口。未删除完整旧业务文件、用户数据库或用户数据，未保留兼容入口或迁移路径。

code-review 固定起点为 `c43f0d2f86244a443c04b46a6774955a6807cb00`，双轴独立评审本次暂存差异，不包含此前 13 个未推送提交。Standards 初审有 1 项 P3：剪贴板出口同时承担凭据复制后，`copyMarkdown` 名称失准；已统一改为 `copyText`，所有调用方更新，业务动作仍独立。Spec 初审有 2 项 P2：切页往返后的旧删除确认／编辑仍可生效，以及 Swift Unicode 等价模型比较沿用旧资格。分别先观察红回归，再让离开 AI 页撤销确认并结束编辑代次、端点／模型改为 UTF-8 精确比较。最终 Standards 为 0 项硬性违反、0 项未解决或新增气味；Spec 为 0 项未解决问题、0 项新增缺失／错误／范围扩张。

修复后的 `rtk proxy ./script/test-isolated.sh --filter 'AIService|AICredential|DailyReportContentTests|DailyReportLayoutTests'` 为 6 个套件、37 个测试通过；全套 121 项与生产纯构建再次通过。旧宿主/UI 调用方在 `copyText` 签名更新后再次仅编译，结果仍为 `TEST BUILD SUCCEEDED`。最终 `rtk proxy git diff --cached --check` 通过。交付前再次只读核对远端 main 仍为 `123948d`，#27/#23 仍开放，阻塞链仍是 #27→#23→#22。

未执行应用启动、生产宿主测试、UI 自动化、真实 Codex／AI、实际键盘／剪贴板／窗口交互、最低 macOS 26.5 运行和父规格三协议真实语义验收；这些不能视为通过。本票只交付已授权的 #27 本地切片，不表示 #20 整体首次交付通过。

## #28 Chat Completions 直接生成验证记录

2026-10-13 至 2026-10-14，仅在本地 `381b830` 上实现 #28；基线已包含 #24（`f88a832`）、#26（`c43f0d2`）、#27（`381b830`）。首次只读核对远端 main 为 `123948d`，#28 原生阻塞项仍为开放的 #24／#26／#27；不推送、不关闭票。

先更新直接生成契约，再观察流程／预算／协议接口缺失的失败，完成最小实现。随后先红再绿覆盖辅助标记突破 20% 上限、schema 计数与实际序列化不一致、原生空／null 工具字段误拒、SSE 已完成但连接未关闭而误超时，以及明确配置失败等待本地写入才撤销资格的回归。

验证入口与行为：

- `ChatCompletionsValidationTests`：保存与三阶段合成探测独立、能力的支持／拒绝／未知、临时故障整份保留、明确配置错误失效、测试不设当前、字段锁定、离开继续或取消、旧回调与 SQLite 基线比较提交。
- `ChatCompletionsHTTPTests`、`ChatCompletionsWireTests`、`ChatCompletionsStreamTests`：沙盒允许的唯一回环端口提供真实 URLSession 假服务；原生鉴权／请求字段／完整路由、schema 的真实编码、非流式完成、SSE UTF-8 分帧与 LF／CRLF／CR、空工具字段、完成后不等连接关闭、取消／迟到回调、连接 30 秒／非流式 300 秒／无有效进展 90 秒。受控时钟推进超过 300 秒的有效流仍可完成，心跳不延长无进展期限；拒绝重定向，无自动重试。403／404／429 与明确错误证据分别核对，可靠 Retry-After 仅供手动重试。
- `OfflineTokenizerTests`：真实 Rust 静态库经正式 C 头桥接，15 项官方 `tiktoken 0.14.0` 夹具分别核对 cl100k／o200k／较大值，特殊 token 字面量按普通文本。流程中的计数错误注入验证停止且没有字节后备；未人为损坏生产内嵌词表。
- `ReportGenerationTests`：全应用单份生成、只读目标与其他日期编辑、复制／预览可用的状态、取消立即解锁、旧结果失效、替换确认刷新、关闭面板不提前取消、失败原子保护、匹配配置错误立即撤销资格、运行中配置例外、完整当天超预算不发送；完整背景与同区已保存历史按日历窗口选择，缺日不补、不读草稿，实际序列化辅助标记也受 20% 限制。成功生成不重读快照，保存失败保留来源，成功清关联。
- `ReportPayloadTests`、`ReportSemanticFixtureTests`：六章严格字段／完成结构、缺章／重复／额外字段／载荷外正文／坏标题拒绝，中文和英文固定标题／占位，凭据遮盖只作用于正文。8 个合成语义场景描述允许事实、完成证据、冲突与认可计划；只校验夹具和确定性契约，不将合成完成结果当作真实模型语义验收。
- `ReportGenerationPrivacyTests`：合成探测和生成经统一流程接入真实 CryptoKit／SQLite／CocoaLumberjack；已保存工作与草稿的边界、真实 SQLite COMMIT 失败的原子保护、整份日志对象的类型化白名单、临时来源与外发编号、所有外发副本及入草稿遮盖。数据库与偏好只包含显式保存允许的内容，没有生成档案或请求缓存；整个流程只扫描一次，不访问真实 Codex。

实际结果：

- `rtk proxy ./script/test-isolated.sh --filter 'ReportGenerationTests|ChatCompletionsValidationTests'`：2 个套件、16 个测试通过。
- `rtk proxy ./script/test-isolated.sh`：评审前全套 33 个套件、157 个测试通过；评审修复后的最终全套为 33 个套件、160 个测试通过。沙盒对其余网络、用户目录、蓝牙与非受控子进程的拒绝回归也通过。
- `rtk proxy ./script/build.sh`：`BUILD SUCCEEDED`，仅构建 arm64 Debug 生产应用；无新增 Swift 编译警告，保留已有 AppIntents 元数据缺少框架依赖的工具提示。实际 Rust 固定为 1.90.0，tiktoken-rs 固定为 0.12.1，锁定依赖与词表在构建时编入静态库，运行时无需 Python／Rust 或词表下载。

清理了 #27 的 Chat Completions 校验占位入口与旧流程初始化签名，所有生产、隔离及旧宿主调用方同步更新。C ABI 使用共用头文件，未保留私有 Swift 符号声明；原辅助预算与 schema 序列化不一致的路径被直接替换。删除逐行判断标题的正则，改用与预览相同的原生 Markdown 结构，并检查拼接后六章不会被未闭合代码块吞掉。没有删除或重置用户数据库／用户数据，没有迁移或兼容分支。

code-review 固定起点为 `381b830ea8cbfd47c161608308c9fcf88cccbb27`，提交前双轴分别审查 `git diff --cached 381b830`，不包含此前 14 个未推送提交。Standards 初审为 0 项硬性违反、0 项可行动气味。Spec 初审发现 2 项 P2 和 1 项 P3：配置提交后的凭据检查等待造成取消空窗、合法水平线／代码字面量被误判为标题、生成失败未刷新关闭确认。先在隔离入口观察全部失败，再将凭据可读性检查移到配置事务前、采用原生 Markdown 标题判断、统一成功／失败／取消的确认刷新。修复后的 `rtk proxy ./script/test-isolated.sh --filter 'ReportGenerationTests|ReportPayloadTests|AIService|AICredential|ChatCompletionsValidation|ReportSemantic|ReportGenerationPrivacy'` 为 9 个套件、43 个测试通过。

初审代理另外执行过一次未走仓库沙盒入口的只读合成 Markdown 解析探针，没有启动应用或访问真实 Codex／AI。正式失败复现、修复回归与最终验证均使用仓库隔离入口。

Spec 复核提出空 ATX 标题可能没有字符 run 的边界。既有坏载荷参数补入裸 `#`／`##` 和引用内空标题，先在 `rtk proxy ./script/test-isolated.sh --filter ReportPayloadTests` 观察 3 项失败；仅在解析副本给潜在 ATX 标题加入可见标记，仍由原生 Markdown 上下文区分代码／转义，实际正文不改写。代码内裸标题保留、空标题拒绝及全部原夹具通过；相关 `rtk proxy ./script/test-isolated.sh --filter 'ReportPayloadTests|ReportGenerationTests|ReportGenerationPrivacy|ReportSemantic'` 为 4 个套件、18 个测试通过。

最后的增量审查提出引用定义 `[r]: #` 接水平线可能误判。正式隔离测试先观察该合法载荷失败，再将解析副本标记限定为行首及引用／列表前缀，保留引用定义 URL。相同 18 项相关测试再次通过，裸列表内空标题拒绝与代码字面量保留均覆盖。

Spec 随后提出 `[r]:\n#\n---` 可能也是合法引用。仓库隔离入口中的原生解析检查保留了 `[r]:` 段落，表明下一行裸 `#` 并未被消费为 URL，实际为空标题；引用容器、列表与多行 label 亦同。此假设未构成实现缺陷，移除未生效的试探保护及临时诊断输出，将这些输入纳入坏载荷参数；正常跨行 URL 和单行引用仍可保留。相关 4 个套件、18 项测试全部通过，生产源码与已经纯构建通过的版本一致。

双轴最终复核均完成：Standards 为 0 项硬性违反、0 项可行动气味；Spec 为 0 项未解决缺失、实现错误或范围扩张。所有已确认问题均修复并回归，待证跨行引用假设由原生解析证据撤回。最后再次运行全套隔离入口，33 个套件、160 项测试通过。

修复后的生产纯构建再次为 `BUILD SUCCEEDED`，只保留原有 AppIntents 工具提示。`rtk proxy bash -n script/build-tokenizer.sh script/test-isolated.sh script/build.sh` 与暂存差异空白检查均通过。2026-10-14 再次只读核对远端 main 仍为 `123948d`，#24／#26／#27／#28 均开放，#28→#27／#26／#24 的原生阻塞关系未变；前置票仍分别被 #23／#25／#23 阻塞。

未执行：生产应用启动、旧宿主／UI 测试、实际窗口／键盘／焦点／剪贴板／睡眠唤醒交互、截图、macOS 26.5／Intel 运行、真实 Codex／AI、实际服务的语义与性能验收、系统日志落盘。直接预算外的完整分批由 #31 承接，真实语义与系统验收由授权后的 #35 承接；本票不表示 #20 整体首次交付完成。

## #29 Responses 校验与直接生成验证记录

2026-10-15，仅在本地 `b1b7320e7b6bc8f64476ce0c7a571c6456c77837` 上实现 #29。先核对 #28 的本地代码、160 项隔离测试记录及纯构建记录；远端 main 仍为 `123948d`，#29 仍被开放的 #28 阻塞，#28 仍被开放的 #24／#26／#27 阻塞。本地继续实现不改变远端阻塞关系。

先更新 Responses 契约，再观察缺少原生适配器、schema 编码、SSE 与共享流程接入的红测试，逐步实现。明确可选字段拒绝被误归类、HTTP 200 内的失败终态被误当截断、错误响应 ID 未核对的回归，均先失败再修复。

验证入口与行为：

- `ResponsesWireTests`：原生 `instructions`／`input`／Bearer／`reasoning.effort`／O／store／truncation／text.format；未设默认值不发送；schema 预算使用实际序列化内容。按 `output` 数组中的已完成 assistant 内容顺序拼接，不使用 SDK 聚合字段；reasoning 不当正文，拒绝／工具／未知／非完成输出不能成文。
- `ResponsesStreamTests`：逐字节 Unicode、组合字符、多行 data、LF／CRLF／CR，原生生命周期及输出项／内容块的完整终态；错误序号／身份／文本／顺序、拒绝、失败、截断、未知项、晚到事件和 `[DONE]` 拒绝。心跳和未知事件不算有效进展，错误终态必须匹配已知响应身份。
- `AIHTTPTests`：唯一允许回环端口的真实 URLSession 假服务，保留完整路由／query／尾斜杠与原生字段；两协议均验证 30 秒连接／300 秒非流式／90 秒无进展期限、拒绝重定向、合法终止不等连接关闭。Responses 原生内容每次推进受控时钟 70 秒，累计超过五分钟仍能完成；不靠任意测试 sleep。
- `ResponsesErrorTests`：明确 stream／text.format 可选拒绝只影响相应探测，正式请求不降级重试；必要字段拒绝、HTTP 200 的失败对象／失败 SSE 与原生鉴权错误正确分类。403／404／429 无可靠代码时不撤销资格，不展示原始服务错误。
- `ResponsesFlowTests`：统一动作贯通保存、三个合成探测、设为当前、固定快照、六章草稿及来源保存；不串用其他协议配置／凭据，不隐式重扫。真实离线 tokenizer 验证 Responses schema 包装的预算临界值，低于直接预算停止且不发送；不支持可选能力时走英文固定文本契约。临时校验故障保留完整旧结论，明确配置错误撤销匹配资格并保留当前身份；保存失败、取消和迟到结果保留原正文与来源。
- `ResponsesPrivacyTests`：原生适配器／SSE 经统一流程接入真实 SQLite／CryptoKit／离线 tokenizer／CocoaLumberjack；探测只含合成输入、实际模型、默认值与 O，不含工作正文或偏好，Key 只进入原生鉴权。临时会话、路径、外发编号和凭据不落库或偏好，整个日志对象只含固定字段；显式编辑后保存并重开，只恢复允许持久化的数据。

实际结果：`rtk proxy ./script/test-isolated.sh` 全套 38 个套件、180 项测试通过，包含原有 Chat Completions 与沙盒拒绝回归；原生端到端、预算、错误和流程相关套件也分别通过。`rtk proxy ./script/build.sh` 为 `BUILD SUCCEEDED`，只构建 arm64 Debug 生产应用；无新增 Swift 编译警告，保留已有 AppIntents 元数据缺少框架依赖的工具提示。

清理了生产入口的 Chat Completions 单协议路由，以及预算中固定使用 Chat Completions schema 的分支；使用一个服务选择入口更新全部调用方。两协议共用纯 SSE 分帧与 JSON 值编码，原 Chat 私有副本移除，协议语义仍独立。`ChatCompletionsHTTPTests.swift` 更名为 `AIHTTPTests.swift`，保持真实 HTTP 测试在同一串行套件使用唯一回环端口。未删除或重置用户数据库／用户数据，没有迁移、兼容入口、生成档案或自动重试。

code-review 固定起点为 `b1b7320e7b6bc8f64476ce0c7a571c6456c77837`，两个独立代理评审本次暂存差异，不包含此前 15 个未推送提交。Standards 初审为 0 项硬性违反、0 项可行动气味；Spec 初审发现 1 项 P2：遗漏原生 `unsupported_value` 参数错误，误归未知而不按明确拒绝处理。必要字段、可选探测与正式请求的参数回归先产生 14 项断言失败，再补入同一固定错误分类，不增加降级重试。修复后 `rtk proxy ./script/test-isolated.sh --filter 'ResponsesErrorTests|ResponsesFlowTests|ChatCompletionsValidationTests|AIHTTPTests'` 为 4 个套件、23 项测试通过。

最终双轴复核：Standards 为 0 项硬性违反、0 项可行动气味；Spec 为 0 项未解决缺失、实现错误或范围扩张。修复后全套再次为 38 个套件、180 项通过，生产纯构建再次为 `BUILD SUCCEEDED`；暂存差异空白检查通过。结束前只读核对远端 main 仍为 `123948d`，#28／#29 仍开放，原生阻塞关系未变。

未执行：应用启动、旧宿主／UI 测试、实际窗口／键盘／焦点／剪贴板／睡眠唤醒交互、截图、macOS 26.5／Intel 运行、真实 Codex／AI、真实端点兼容性／语义／性能验收、系统日志落盘。完整分批由 #31 承接，真实系统与三协议组合验收由 #35／#36 承接；隔离假服务不代表真实兼容，#20 整体验收未完成。本次不推送、不关闭 Issue。

## #30 Messages 校验与直接生成验证记录

2026-10-15，仅在本地 `06da0cf044876ddadb0c0e8879188d3be128770b` 上实现 #30。工作区起始干净，基线已包含 #28 的 `b1b7320` 与 #29 的 `06da0cf`。只读核对远端 main 为 `123948d`，#30 仍被开放的 #28 阻塞，#28 的原生阻塞项仍为开放的 #24／#26／#27；本地继续实现不解除远端阻塞。

先更新 Messages 契约，再通过隔离入口依次观察未接入原生请求、缺少原生 schema、未接入 SSE、流程校验被拦截、原生错误分类及字段拒绝证据的失败，逐步完成最小实现。回环 HTTP 取消测试另复现事件流因取消直接结束却被误报坏响应的竞态，传输在事件接收及结束边界检查取消，三协议均回归。

验证入口与行为：

- `MessagesWireTests`：原生 x-api-key／固定版本头／system／messages／max_tokens；温度 0 与未设置不同，thinking 默认／关闭／adaptive，effort 与 schema 共存但不虚构其他协议字段。仅提取 text，思考不进入正文；拒绝、截断、工具、未知内容、坏身份或缺少结束状态失败。事实提取／归并／成文三个业务意图均使用原生 schema 编码。
- `MessagesStreamTests`：逐字节 Unicode、组合字符、多行 data、LF／CRLF／CR，thinking／signature／redacted_thinking 与文本块的独立顺序／索引／类型；缺少起止、签名、块完成或 message_delta／message_stop，事件冲突、工具、拒绝、截断、空文本及晚到内容均拒绝。ping／未知事件不冒充进展，允许合法的多个 message_delta，但 usage 不能替代结束状态。
- `MessagesErrorTests`：HTTP 与 SSE 原生错误、受支持的明确字段拒绝、必要控制与其他协议字段拒绝、对应可选探测与正式请求的区别；每次失败只发送一次。403／404／429 或模糊 invalid_request_error 不猜 Key／模型／配额；账单错误不推断余额不足，错误提示不含服务原文。
- `AIHTTPTests`：唯一允许回环端口的真实 URLSession 假服务，原生非流式及 SSE、完整路由／query／尾斜杠；三协议验证重定向拒绝、30 秒连接／300 秒完整结果／90 秒无进展、立即取消、合法结束不等连接关闭，以及可靠 Retry-After。Messages thinking 进展每次推进受控时钟 70 秒，累计超过五分钟仍正常完成，不使用任意测试 sleep。
- `MessagesFlowTests`：同一动作／状态接口贯通显式三探测、当前身份与资格、确认快照、中文六章、实际来源、编辑及保存失败／成功；不串配置／Key，不隐式重扫。英文固定文本回退、原生 output_config（含 effort）的真实 tokenizer 预算临界值、完整当天不裁尾、校验临时未完成保留旧结论、取消／离开／迟到回调保护均通过。
- `MessagesPrivacyTests`：真实 SQLite／CryptoKit／tokenizer／CocoaLumberjack 配合原生适配器，验证合成探测不带工作／偏好、Key 只在原生鉴权、每次实际输入及入草稿遮盖、失败原子保护、明确编辑／复制／保存及重开。正文／思考／错误／来源等唯一合成标记不进入日志对象、UserDefaults 或禁止的数据库出口，保存前没有持久草稿。

实际结果：

- `rtk proxy ./script/test-isolated.sh --filter 'Messages|ResponsesErrorTests|ChatCompletionsValidationTests|AIHTTPTests|AIServiceSettingsTests'`：8 个套件、53 项通过；新增隐私集成单独通过。字段验证回归随后纳入全套。
- `rtk proxy ./script/test-isolated.sh`：最终全套 43 个套件、207 项通过，包含原两协议与沙盒拒绝能力回归。首次全套曾有一次回环假服务创建 `.setup` 失败，后续两次完整入口未复现；未据此推断生产端问题。
- `rtk proxy ./script/build.sh`：`BUILD SUCCEEDED`，仅构建 arm64 Debug 生产应用；无新增 Swift 编译警告，保留已有 AppIntents 元数据缺少框架依赖的工具提示。

code-review 固定起点为 `06da0cf044876ddadb0c0e8879188d3be128770b`，两个独立代理评审本票暂存差异。Standards 初审为 0 项硬性违反、0 项可行动气味；Spec 初审发现 1 项 P2：遗漏已知模型明确拒绝 disabled thinking 的原生提示，误归未知而保留对应基线资格。先补文档及 HTTP／SSE 回归，亲检两项断言失败，再补有限前缀识别，不增加模式、改参或重试。`rtk proxy ./script/test-isolated.sh --filter 'MessagesErrorTests|MessagesFlowTests|MessagesPrivacyTests'` 为 3 个套件、14 项通过。最终双轴复核均为 0 项未解决；修复后完整隔离测试 43 个套件、207 项通过，纯构建再次 `BUILD SUCCEEDED`，暂存空白检查通过。结束前只读核对远端 main 仍为 `123948d`，#30／#28 仍开放，原生阻塞关系未变。

清除了 Messages 的未接入校验拦截及占位文案；schema 预算入口改为接收实际配置，所有调用方同步更新。未删除文件、数据库或用户数据，未增加迁移、兼容分支、预算调度副本或生成档案。执行期间工程文件出现仅键顺序调整的外部改动，保留并排除在本票提交之外。

未执行：应用启动、旧宿主／UI 测试、实际窗口／键盘／焦点／剪贴板／睡眠唤醒交互、截图、macOS 26.5／Intel 运行、真实 Codex／AI、真实端点兼容性／语义／性能验收、系统日志落盘。完整分批由 #31 承接，真实组合证据由 #36 承接，授权系统／语义验收由 #35 承接；#20 整体验收未完成。本次不推送、不关闭 Issue。

## #31 完整长输入与有限分批验证记录

2026-10-16，仅基于本地 `2df5a96009c67f4727d71907225d6b81ec3bb56d` 实现 #31。先读根 AGENTS、#31、父 #20 全文与评论、CONTEXT 及全部相关 ADR，核对本地 #28／#29／#30 的实际代码；只读核对远端 main 为 `123948d`，#31 的原生阻塞项仍为开放的 #28。本地实现不解除远端阻塞，不推送、不关闭 Issue。起始工程文件已有两处键顺序调整，保留并排除在本票暂存范围之外。

先更新输入、计划与交付文档，再从统一流程的超预算失败回归开始逐步实现。超长单轮保全字符、执行接入、真实进度、会话边界优先、归并不能清空必要上游事实、等待确认期间脱敏失败可见，以及大量无相关内容的小轮次不携带无用整轮清单，均亲检失败输出后修复。没有复制业务实现或另建协议路径。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --filter 'ReportBatch|ReportGenerationTests|ResponsesFlowTests|MessagesFlowTests'` | 7 个套件、41 项通过，含并发 1／3／8、8 种坏中间结果、必要失败／取消及三种原生协议参数用例。 |
| `rtk proxy ./script/test-isolated.sh --filter DailyReportLayoutTests.batchPlan` | 1 项通过：最小 600×300pt 计划面板、860pt 进度区、900×620pt 日报均通过无 NSWindow 的原生内容测量。 |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 arm64 Debug 纯构建；无新增 Swift 编译警告，只有既有 AppIntents 元数据跳过提示。 |
| `rtk proxy ./script/test-isolated.sh` | 评审前 47 个套件、226 项通过；评审修复后的最终全套为 47 个套件、227 项通过，包含三协议与沙盒拒绝能力回归。 |
| `rtk proxy git diff --cached --check` | 通过；暂存范围仅本票文件，不含工程文件无关变化。 |

- `ReportBatchGenerationTests`：实际离线 tokenizer 规划完整当天输入；完整会话优先，超长单轮按扩展字素簇拆分并核对全部 UTF-8 字节、助手最终回复、角色／时区／日期／序号／结果状态；部分轮次不能确认完成。有限多层及最坏可见预算、实际已能成文立即停层、无缩减／结构／引用／覆盖／预算失败终止；4／5 次及 4–5 次范围在首笔请求前确认，确认变更重算；依赖屏障、乱序稳定、并发边界、整体失败／取消和旧正文保护。
- `ReportBatchContextTests`：提取只用对应会话背景、归并不重复背景、成文只用同区已保存历史；完整辅助单元超预算跳过并继续，实际序列化仍受 20% 上限，来源日期只记录实际使用者。运行中 C／O／并发／语言／偏好／回看和历史正文变化不改任何后续批次；O 变化使新生成待复验，既有任务仍用原 O。等待确认时遮盖失败提示可见且取消不发送。
- `ReportBatchWireTests`：同一请求经过三个真实原生 Adapter 和受控传输，独立摘要块保持顺序及全部文本，每种协议保留自身鉴权／O／必要控制和 schema 编码。没有真实端点访问。
- `ReportBatchPrivacyTests`：统一流程接入真实 SQLite／CryptoKit／离线 tokenizer／CocoaLumberjack 与受控 AI、Codex Adapter；原文、Key、临时来源与中间事实不进入磁盘或日志，中间事实不进入六章草稿／剪贴板，显式保存并重开只恢复允许的正文与设置。分批且未裁剪不标降级，真实辅助裁剪才记当次已知损失。

清理了旧 `needsBatching` 停止错误／提示、直接规划中的重复遮盖与辅助预算实现、仅用于旧入口的转发方法、硬编码单请求进度及无用偏好存储副本；所有调用方同步更新。没有删除完整源文件、数据库或用户数据，没有迁移、兼容分支、自动重试、逐条证据档案或恢复副本。

未执行：生产应用启动、旧宿主／UI 测试、真实窗口／键盘／焦点／剪贴板／睡眠唤醒交互、截图、macOS 26.5／Intel 运行、真实 Codex／AI、真实端点语义／性能／三协议组合及系统日志落盘。#34／#36 承接三协议汇合与组合证据，#35 承接获授权后的真实系统／语义验收；本票结果不代表 #20 整体验收完成。

code-review 固定起点为 `2df5a96009c67f4727d71907225d6b81ec3bb56d`，两个独立代理分别评审本票暂存差异，不包含此前 17 个未推送提交及工程文件无关变化。Standards 初审为 0 项硬性违反、1 项 P3 可行动气味：两个未使用入口；删除后复核为 0 项未解决。Spec 初审发现 1 项 P2：离线规划完成的规模确认会覆盖已打开的关闭／退出保护面板。文档先补契约，统一流程的关闭／退出两参数回归均先失败，再将回调改为保留并刷新原面板；旧确认失效、返回编辑保留计划、重新查看并确认才外发均覆盖。Spec 复核为 0 项未解决缺失、实现错误或范围扩张。

评审修复后的 `rtk proxy ./script/test-isolated.sh --filter 'ReportBatchContextTests|ReportGenerationTests|DailyReportWindowTests'` 为 3 个套件、21 项通过。随后完整隔离入口 47 个套件、227 项通过，生产纯构建再次 `BUILD SUCCEEDED`，只保留既有 AppIntents 工具提示；暂存空白检查通过。Standards 对最终生命周期增量再次复核，仍为 0 项硬性违反、0 项未解决可行动气味。结束前只读核对远端 main 仍为 `123948d`，#31／#28 仍开放，原生阻塞关系未变。

## #32 生成生命周期验证记录（2026-10-20）

仅基于本地 `4db34140b5b229bf7d7daab0d7a995d91a13b91c` 处理 #32。先读 AGENTS、该票与父 #20 的完整正文／评论、CONTEXT 和相关 ADR，并核对本地 #28–#31 前置实现。只读核对远端 main 为 `123948d`，#32 仍被开放的 #31 阻塞，#31 仍被开放的 #28 阻塞。本地实现不解除远端阻塞。起始工程文件已有两处键顺序变化，保留并排除，SHA-256 与起始一致。

先补 [生成生命周期契约](generation-lifecycle.md)，再在既有统一流程与真实传输边界补行为测试。亲检以下回归失败后完成最小修复：Messages 仅提及字段就被误判为参数拒绝；流内错误及 HTTP 200 非流式错误丢失限流分类或可靠等待时间；在成文进度回调中取消仍派发请求；网络、临时服务和未知错误共用模糊提示。删除宽泛字段前缀判定与合并提示，复用既有原生证据分类，补足计数／进度到派发之间的取消检查。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --filter 'AIHTTPTests|MessagesErrorTests|ResponsesErrorTests|ChatCompletionsValidationTests'` | 4 个套件、32 项通过，含三协议限流及实际经过时间参数用例。 |
| `rtk proxy ./script/test-isolated.sh` | 全套 49 个套件、243 项通过，无编译警告或测试失败。 |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 arm64 Debug 纯构建；无新增 Swift 编译警告，仅既有 AppIntents 元数据跳过提示。 |

- `ReportGenerationConfigurationTests`：直接／提取／归并阶段的端点、模型、默认值、凭据替换／删除、当前切换共 18 组；保存失败保持旧配置和任务。O 变化后旧任务仍用旧 O，复验新 O 后旧基线的四种失败不能覆盖新资格。待确认计划遇到 C／O／并发／语言／偏好／回看、来源或实际历史变化，必须重新规划及确认，陈旧按钮不发送。
- `ReportGenerationLifecycleTests`：三阶段与十类必要失败的 30 组组合保护完整原稿及来源，仅明确配置错误撤销匹配资格；忽略取消的适配器迟到成功／失败不能恢复旧结果。关闭／退出合并全部日期草稿并刷新确认，数据源改变保留固定快照，有效时区变化取消受影响范围；模拟整次经过一小时不设置全局短时限。可靠等待结束只开放手动重试，使用最新保存偏好／历史及已确认快照，不自动扫描或发请求。既有分批上下文测试继续覆盖运行中 C／O／并发／语言／偏好／回看固定。
- `AIHTTPTests`：三协议真实回环 URLSession 对 HTTP 错误、原生非流式错误及流内错误保留可靠 `Retry-After`。受控时钟分别模拟连接 30 秒、非流式 300 秒、流式 90 秒已经经过，但计时器尚未恢复调度，迟到响应仍超时。既有心跳、有效进展、终止、重定向及真实传输取消回归继续通过。
- `ReportBatchPrivacyTests`：实际临时 SQLite／CryptoKit／CocoaLumberjack 出口同时覆盖成功、必要失败和取消；原稿与整份来源原子保留，不写部分日报、恢复档案或中间事实。仅显式保存后的正文可在重开数据库后恢复；合成敏感标记不进入日志对象或禁止的磁盘出口。

code-review 固定起点为 `4db34140b5b229bf7d7daab0d7a995d91a13b91c`，按先评审后提交的顺序，由两个独立代理检查本票 17 个暂存文件，排除既有未暂存工程文件。Standards 为 0 项硬性违反、0 项可行动气味；Spec 为 0 项缺失、实现错误或范围扩张。暂存空白检查通过。结束前再次只读核对远端 main 仍为 `123948d`，#32／#31／#28 仍开放，原生阻塞关系未变。

未删除完整源文件、数据库或用户数据，没有迁移、兼容入口、自动重试、第二套协议或生成档案。仅清理上述错误判定／提示的旧分支，所有调用方继续使用同一流程与传输入口。

未执行：应用启动、旧宿主／UI 测试、真实 Codex／AI、真实端点限流／兼容性／语义／性能、系统睡眠唤醒、原生窗口／焦点／键盘／剪贴板、截图、macOS 26.5／Intel 运行或系统日志落盘。内容删除的具体存储操作由 #33 承接，三协议汇合／组合和授权系统验收仍由 #34–#36 承接；这些隔离结果不代表父 #20 整体验收。本次不推送、不关闭 Issue。

## #33 内容管理与存储演进验证记录（2026-10-21）

仅基于本地 `9d1f1f0d126d6b0e27bdcdd44fc22ccd2a5f5ce3` 实现 #33。先读 AGENTS、该票、父 #20 完整正文／评论、CONTEXT 与相关 ADR，核对本地 #28–#32 前置实现。只读核对远端 main 为 `123948d`，#33 原生阻塞项 #28 仍开放；本地实现不解除远端阻塞。保留并排除起始工程文件的两处键顺序改动。用户明确允许本票迁移日报专用库及旧密钥兼容，既有模型／蓝牙数据不迁移，不操作用户数据库。

先更新 [存储管理契约](daily-report-storage-management.md) 及相邻文档，再逐步补删除、清空、迁移和重置的行为回归，亲检缺少动作／存储契约的失败输出后实现。测试复用生产 `DailyReportFlow` 动作／状态和真实 SQLite／CryptoKit；所有数据库、凭据及恢复副本均为独立临时合成数据。

| 实际命令 | 结果 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --filter 'ReportContentManagementTests|ReportStorageManagementTests|DailyReportLayoutTests'` | 3 个套件、25 项通过，含多组参数用例。 |
| `rtk proxy ./script/test-isolated.sh` | 评审前全套 51 个套件、260 项通过；评审修复后的最终全套为 51 个套件、261 项通过，包含三协议、隐私及沙盒拒绝能力回归。 |
| `rtk proxy ./script/build.sh` | `BUILD SUCCEEDED`，生产 arm64 Debug 纯构建；无新增 Swift 编译警告，仅既有 AppIntents 元数据跳过提示。 |

- `ReportContentManagementTests`：单份确认覆盖共存草稿，范围变化使旧按钮无效；删除失败保留正文／草稿／候选选择，成功才清内存。清空列出全部时区与各类数量，保留设置／凭据，成功清全部快照和选择；关窗计数归零。排队旧编辑、取消后迟到生成成功、单份／全部删除与提交失败组合均不能写回；故障重置有独立确认且不访问网络。
- `ReportStorageManagementTests`：真实 schema 1–4 逐级迁移、Markdown 原文与逻辑凭据版本保全、旧封装重加密、旧密钥读取、未知／认证错凭据只隔离对应配置。真实读锁阻止提交时删除及迁移回滚；失败重加密不改旧封装或版本。专用子进程在实际热 journal、迁移中断及重置三个阶段退出，验证 SQLite 正常恢复、独占锁、仅继续已确认重置和无旧库备份。停机整体复制／恢复合成目录能带回已删日报、旧 Key 与设置，来源未检查且无草稿恢复。
- `DailyReportLayoutTests`：内容管理、删除／清空确认在最小布局下以无 NSWindow 的 `NSHostingView` 测量；危险按钮默认取消，具体控件保留启用／禁用指针样式。此结果不代表真实窗口或键盘验收。

清理内容管理占位页、占位专用图标／摘要属性，以及直接拒绝所有历史 schema 的旧路径；存储锁移至统一目录所有权，全部调用方同步更新。未删除完整源文件或用户数据。测试子进程只删除各自临时日报库，生产删除／重置能力未对用户库执行；不新增导入、自动备份、永久删除账本或隐藏旧库副本。

code-review 固定起点为 `9d1f1f0d126d6b0e27bdcdd44fc22ccd2a5f5ce3`，两个独立代理分别检查本票 31 个暂存文件，排除工程文件无关改动。Standards 初审为 1 项 P3：常规设置文档仍称 schema 4 及内容管理由后续票承接；同步后复核为 0 项规范违反、0 项可行动气味。Spec 初审为 1 项 P2：重置等待旧写入时，再次打开窗口会另起旧库加载并覆盖重置队列，旧快照可能回填正文或凭据。先补文档及 `.report`／`.settings` 两参数屏障回归，亲检重置后仍回填一份旧日报的失败输出，再限制提交期间只展示窗口、不另起存储加载；复核为 0 项未解决缺失、实现错误或范围扩张。

`rtk proxy ./script/test-isolated.sh --filter 'ReportContentManagementTests|ReportStorageManagementTests|DailyReportWindowTests'` 为 3 个套件、22 项通过。修复后完整隔离入口 51 个套件、261 项通过，纯构建再次 `BUILD SUCCEEDED`，仅既有 AppIntents 工具提示；暂存空白检查通过。结束前只读核对远端 main 仍为 `123948d`，#33 和其原生阻塞项 #28 仍开放。

未执行：应用启动、旧宿主／UI 测试、真实 Codex／AI、用户库迁移或重置、真实人工目录替换、Finder 打开、系统窗口／焦点／键盘／剪贴板／睡眠唤醒、截图、macOS 26.5／Intel 运行及系统日志落盘。#34–#36 的组合与授权验收、父 #20 整体验收仍未完成。本次不推送、不关闭 Issue。
