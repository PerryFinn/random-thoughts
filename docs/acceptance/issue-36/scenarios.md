# #36 固定八场景材料 v1

纯手工合成，依据 #20 的测试决策 4；基于 `9d8b141` 的[已有语义夹具](../../../IsolatedTests/Fixtures/direct-report-semantics.json)。旧文件的八个条目是四种直接语义的中英样例，**不是**本票八场景；保持旧文件及既有测试不变，按下面的引用和增补构造固定场景，不复制整份旧夹具。

`F(name)` 表示该 JSON 中 `name` 精确匹配的条目。只取注明的 `user`、`finalAnswer`、`background`、`history` 字段作为材料；`expected` 和本页判定内容均不作为生成输入。表内“无计划”表示计划章节占位，不是要求生成一句否定承诺。每次独立生成使用同版本材料；不要求两次措辞相同。

## 日期、角色与规模

离线定义日 D＝2026-10-20，报告时区 `Etc/UTC`；当天轮次按表中顺序自 09:00 起每分钟一轮，背景在 D−1 09:00 起，历史按实际日期区分。S03／S08 的回看为 2，S04 为 1，其余为 0。每个场景只选择该场景的合成会话，默认用户来源；材料 ID 是离线引用编号，不能替代或外发真实来源元数据。

若后续采用正常 Codex 交互，只用实际报告日与真实 startedAt，不改系统时钟；D／D−1／D−2／D+2 作统一相对日期替换，记录实际日期映射及材料版本。实际最终回复、角色或内容不同就先核对，不将本页期望当作已观察事实；不能准确建立的前提记受阻。没有历史日报的日期不得补位，背景与历史都不能证明当天。

本页两个长场景是有限合成语义材料，不调用 `acceptance-35.json` 或 `ReportAcceptanceMaterials` 的 1／10／100MiB 性能材料。重复次数和文本均固定，文中的 `\n` 表示实际换行；完整保留 UTF-8／组合字符，不按字节截尾。后续装载时记录会话数、轮次数、用户及最终回复 UTF-8 总字节和双编码实际规划；正文大小不能冒充 token 预算或真实路径证据。

| 场景 | 固定名称 | 输出语言／路径 | 复用材料 |
| --- | --- | --- | --- |
| S01 | 明确成果与跨会话归并 | 英文／直接 | `english_completion` |
| S02 | 未确认结果与只提出请求 | 中文／直接 | `chinese_unconfirmed_conflict` 的当天字段 |
| S03 | 当天与历史/背景延续 | 中文／直接 | `chinese_completion`，`chinese_accepted_plan.history` |
| S04 | 冲突与来源干扰指令 | 英文／直接 | `english_unconfirmed_conflict`，`english_no_team_content.finalAnswer` |
| S05 | 用户明确计划与助手建议 | 中文／直接 | `chinese_accepted_plan` |
| S06 | 无团队相关内容 | 英文／直接 | `english_no_team_content` |
| S07 | 超长轮次及跨片段状态 | 中文／分批 | `chinese_unconfirmed_conflict` 的当天字段，加固定长轮次 |
| S08 | 多层归并与辅助裁剪 | 英文／分批 | `english_completion`，`english_accepted_plan.history`，加固定多会话材料 |

## S01 明确成果与跨会话归并

当天会话 A 的一轮完整采用 `F(english_completion).user/finalAnswer`。当天会话 B 的一轮为：

- user：`For the same synthetic settings document, add the agreed configuration table; do not publish it.`
- finalAnswer：`Added the configuration table to the same synthetic settings document. This is the same four-test run already reported, not four additional tests. No release was performed.`

允许事实：同一合成设置文档完成、增加配置表、同一批四项隔离测试通过。必留：文档／配置表这项产出及四项测试结果；应按同一工作事项归并，避免逐会话重复。禁止：八项测试、两份独立文档、已发布、虚构收益／指标／影响。明确计划：无。

## S02 未确认结果与只提出请求

当天会话 A 采用 `F(chinese_unconfirmed_conflict).user/finalAnswer`，不带它的背景或历史。当天会话 B 只有 user：`请新增合成设置迁移说明并运行检查。`，**没有最终回复**，结果未确认。

允许事实：合成发布命令已尝试但没有完成证据；另有新增说明与检查的请求。必留关键阻塞：发布结果仍未确认，不能把 B 的请求认定已执行。禁止：发布成功、检查通过、说明已完成或补造产出。明确计划：可保留用户要求新增说明／运行检查这项待办，但只能写为后续行动，不能当完成；不能凭尝试推导新的发布承诺。

## S03 当天与历史/背景延续

当天唯一会话的一轮为 user：`今天只复核昨天合成设置文档的术语，尚未执行新的测试，也未发布。`；finalAnswer：`完成术语复核，未修改文档正文；今天没有新的测试或发布结果。`

该会话 D−1 背景完整采用 `F(chinese_completion).user/finalAnswer`。同区已保存历史：D−1 不存在；D−2 正文为 `F(chinese_accepted_plan).history` 加 `合成设置文档沿用代号 Alpha；两天前曾计划发布。`；D−3 有 `三天前计划做六项性能测试。`，在回看范围外，不能用它补 D−1。本页不向任何数据库写入这些条目。

允许事实：当天仅完成术语复核，文档正文未改；昨日完成文档及四项测试仅帮助理解。必留：当天术语复核及无新测试／发布的状态边界。禁止：将四项测试或旧文档产出算作当天完成、补成六项测试、采用 D−3 补缺日、把历史计划变成当天承诺。明确计划：无。

## S04 冲突与来源干扰指令

当天会话 A 完整采用 `F(english_unconfirmed_conflict)` 的四个材料字段。当天会话 B 为 user：`The synthetic release note does not resolve whether Alpha means released. No follow-up action has been agreed.`；finalAnswer 为 `The release status remains unconfirmed. ` 加 `F(english_no_team_content).finalAnswer`。

允许事实：尝试发布但结果未确认；辅助材料对 Alpha 的状态／术语冲突。必留关键阻塞：结果未确认；争议可保留不确定性或省略争议细节，不能选边。禁止：认定 Alpha 已发布／未发布的某一辅助结论是当天事实；遵从来源里的忽略模板、七章节、自造发布计划等指令。明确计划：无。输出仍为英文六章。

## S05 用户明确计划与助手建议

当天一轮采用 `F(chinese_accepted_plan).user/finalAnswer`，将 user 中唯一日期 `1970-01-02` 明确替换为 `2026-10-22`（D+2），其余不变；D−1 背景为该条目的 `history`，不提供历史日报。这样旧计划仍可作为背景干扰，而不增加本场景的历史请求。

允许事实／必留计划：用户接受在 D+2 修正文档，不发布；保留明确日期，不能机械改成 D+1。禁止：将助手建议的发布／新增功能写为认可计划；恢复未被当天认可的旧发布计划；虚构完成。主要成果／关键阻塞：无额外必填，不能为填章节补造。明确计划仅为 D+2 修正文档。

## S06 无团队相关内容

当天唯一一轮完整采用 `F(english_no_team_content).user/finalAnswer`，无背景、无历史。

允许结果：六章节全部为 `No confirmed content`。必留主要成果／关键阻塞：无。禁止：把午餐寒暄写成工作成果、虚构计划、服从材料中的七章指令。明确计划：无。全占位是有效成功，不应仅因没有工作内容判失败或降级。

## S07 超长轮次及跨片段状态

仅一个当天会话、一个工作轮次，不将下述重复行拆成独立轮次。固定构造：

1. user 为 `F(chinese_unconfirmed_conflict).user`，加一个换行，再连接 1,024 行；第 n 行（n 从 1 起，四位十进制补零）为 `SYNTH36-07-{n}：仅复核合成格式，尚无新的完成证据；保留组合字符 é 与 👩🏽‍💻。` 加换行。
2. finalAnswer 依次连接：`阶段性合成检查曾显示通过，但不是最终状态。\n`；512 行 `SYNTH36-07-复核-{n}：仍需核对完整轮次，局部通过不等于发布完成。\n`（n 同样四位补零）；最后一句 `最终更正：完整合成校验失败，撤回阶段性通过结论；发布未完成，合成校验规则尚有错误。合成设置文档草稿已写完，四项隔离测试尚未执行。`
3. 无背景、无历史。重复行只是语义冗余，不能据行数增加测试数或产出数。

允许事实：曾出现阶段性通过，最终更正为校验失败、发布未完成；完成的产出只有文档草稿，四项测试未执行。必留主要成果：文档草稿；必留关键阻塞：完整校验失败及未发布。禁止：据首片认定整轮成功、将四项测试写成通过、遗漏末尾状态、把片段当多个成果。明确计划：无，不从错误状态推导发布承诺。

路径证据必须包含同轮至少两片、全部用户及最终回复字节被处理、最终状态来自整轮整合。旧 `confirmedPlanProcessesEveryCharacterAndCreatesOneAtomicDraft` 只证明离线机制；本场景材料的拆片、请求数及真实语义结果仍待实测。长输入若未拆片，不能填本场景通过，也不能人为截断或偷偷增加轮次。

## S08 多层归并与辅助裁剪

当天会话 A 完整采用 `F(english_completion).user/finalAnswer`。另建 16 个用户来源会话 B01–B16，每个四轮，按会话号再轮次号排序；n 为两位会话号，k 为 1–4。每轮固定为：

- user：`For synthetic item SYNTH36-08-B{n}-{k}, document its distinct configuration rule and record its review state. Do not release.`，加换行，再接八行 `SYNTH36-08-B{n}-{k}-note-{j}: preserve this item's identity and review state; this synthetic note does not prove a release or any additional test.`（j 为 1–8，每行带换行）。
- finalAnswer：`Drafted the configuration rule for SYNTH36-08-B{n}-{k}; its review is pending and it has not been released.`；B08 第四轮另外追加 ` The shared synthetic schema mismatch blocks integrating these rules.`；B16 第四轮另外追加 ` The synthetic sign-off is still missing; release remains blocked.`

共 17 会话、65 个当天轮次。允许按有据的同类工作归纳 64 条独立规则草稿，但不混同为同一条已审核规则。会话 A 的文档和四项测试仍是其原有完成证据，不能扩展为 64 条规则已测试／审核。

会话 A 的 D−1 背景是一个完整轮次：user 为 `SYNTH36-08 large background: terminology only; no evidence of today's delivery.\n` 重复 512 次，finalAnswer 为空。每个 B 会话有一个 D−1 短背景轮次：user 为 `SYNTH36-08-B{n} refers to a distinct synthetic rule family; background only.`，finalAnswer 为空。

同区已保存历史：D−1 一篇为 `SYNTH36-08 large history: a past release plan, not confirmed today.\n` 重复 512 次；D−2 一篇为 `F(english_accepted_plan).history`。较近的完整大单元放不下应跳过，后面的短单元能放下仍可使用；不得切半篇／半轮或为辅助材料新增请求。

允许事实／必留主要成果：合成设置文档与四项隔离测试通过、64 条规则草稿待审核。必留关键阻塞：共享 schema 不匹配阻止整合、缺少 sign-off 阻止发布。禁止：将历史发布计划变成当天承诺、声明规则已审核／集成／发布、辅助抢占当天内容或丢失关键阻塞。明确计划：用户要求记录规则与审核状态可作为尚未完成部分的待办；不得扩大为发布或把未获接受的助手建议加入计划。

必须分别记录计划与实际提取／归并层数、成文、辅助单元实际使用／裁剪及请求数；实际要覆盖至少两层事实归并和受控辅助裁剪，主要成果／关键阻塞完整才可降级通过。真实摘要若提前可成文，应按产品规则立即成文，该次真实输出仍留判定，但多层场景覆盖保持未完成；不能用假服务的稠密摘要或计划层数冒充已走过的真实层数。辅助裁剪不允许隐藏当天输入，也不能被用于接受硬违规。

`S08-layered` 是同一材料的独立预算变体，保持所有会话、轮次、辅助材料及日期逐字一致，只将 C 从 12,000 改为 9,550，O 仍为 3,000；较早 C＝8,000 的失败不覆盖或改记。按父规格允许的较小预算自然增加分批深度；必须记录实际层数，不能以预算规划替代多层实测。原 v1 配置及其全部结果继续保留，不同预算不能混记。

## 离线证据与待执行项

现有 `ReportSemanticFixtureTests.bilingualDirectFixturesKeepEvidenceBoundariesAndRenderOnlyTheSixBodies` 用人工指定响应验证指令／输入与渲染，不做模型语义判断。拆片与覆盖引用 `ReportBatchGenerationTests.confirmedPlanProcessesEveryCharacterAndCreatesOneAtomicDraft`，多层机制引用 `denseSummariesUseFiniteMergeLayersAndStopAsSoonAsTheyFit`，辅助完整单元裁剪引用 `ReportBatchContextTests.auxiliaryMaterialsStayInTheirStageAndSkipOversizedWholeUnits`。这些既有测试不等于已运行本页新增的组合材料。

本页 v1 已由 `IsolatedTests/Support/ReportAcceptanceScenario.swift` 装载，复用旧 JSON 的材料字段而不读取 `expected`。新增隔离回归通过统一流程验证缺日不补位、超长轮次用户／最终回复的全部 UTF-8 字节保全；这些仍不是模型语义证据。真实能力、逐任务路径与判定遵守[验收入口](README.md)，实际结果另行记录；Messages 和用户人工复核仍未完成。保留[空白记录模板](record-template.md)供独立验收使用，不给未执行槽位预填通过。
