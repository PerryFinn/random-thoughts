# #35 离线性能与 App 包体验收记录

记录日期：2026-10-30（Asia/Shanghai）。执行者：Codex Agent。仅承接用户授权的离线性能／包体部分；#35、父 #20 的真实 Codex、原生 UI／系统和 #36 真实模型语义验收仍未完成。

## 基线、前置与授权

- 起点与远端 main 均为 `6f41f8a9e60d3c1356b0afec274734766114a30e`。#35 OPEN，原生阻塞为 OPEN 的 #34；#34 的 #29／#30／#32／#33 均 OPEN。#31 也 OPEN。对应本地提交 `06da0cf`、`2df5a96`、`4db3414`、`9d1f1f0`、`a62e7ec`、`c74eb42` 全为起点祖先。本地测量不解除远端阻塞。
- 已读当前 AGENTS、#35／父 #20 完整正文及评论（均无评论）、验收清单／模板、CONTEXT、三份 ADR 和测试隔离说明。仅做本票离线入口、实测、评审和本地提交；不认领／评论／推送／关票。
- 不启动生产应用，不执行旧宿主／UI 测试，不调用真实 Codex／AI，不操作用户数据库。压力材料完全合成，不外发。运行期间没有新增迁移、兼容路径、产品调试入口或运行档案。
- 既有 `project.pbxproj` 两处排序变化保留并排除，起始 SHA-256：`ae1aa7492c840053d3114b948f5437dc66323aee0fac302c326184e090ad6c1b`。

## 环境与方法

| 字段 | 实测值 |
| --- | --- |
| CPU／统一内存 | Apple M3 Max／38,654,705,664 字节（36GiB） |
| 架构／系统 | arm64／macOS 27.2（26B123）；当前开发系统，不代表最低 26.5 的原生验收 |
| Xcode／Swift／SDK | Xcode 27.1（27A9275）／Swift 6.4（swiftlang-6.4.0.34.1）／macOS 27.0 SDK |
| Rust 内核 | rustc 1.90.0（1159e78c4）；固定 Cargo.lock，release 内核 |
| 测量构建 | SwiftPM swiftbuild，Release（Swift `-O`／整模块优化及 `-enable-testing`），无生产 TEST_HOST |
| 输入材料 | `acceptance-35.json` 版本 1、种子 35、2026-10-20／Etc/UTC |
| 材料 SHA-256 | `5996d93f07dd12a995843acf1bdb3a7e21ffde1a03e8f43fbe72fb612348fc7b` |
| C／O／I | 65,536／16,384／39,321；生成协议为受控 Chat Completions 意图，结构化能力开启，无网络传输 |

每个规模／阶段独立新进程，进程内运行首次和重复各一次；调度分别测并发 1／3／8。小 10 会话／100 轮／1MiB，中 100／1,000／10MiB，大 1,000／10,000／100MiB，中大首轮均为 2MiB；总字节包含用户与最终回复，混合中英／Swift／组合字符／emoji。构造完成后核对实际总量，扫描结果逐字段核对，规划片段按会话／轮次重建并比较 UTF-8 字节。

阶段计时使用单调 [DispatchTime.uptimeNanoseconds](https://developer.apple.com/documentation/dispatch/dispatchtime)，不包含系统睡眠。未清理系统文件缓存，不将“新进程首次”称为冷磁盘样本。材料构造、扫描夹具编码和调度计划准备不计入阶段时钟；调度准备另表记录，首次调度时 tokenizer 已加载。规划包含真实尽力脱敏、实际 JSON 及原生结构格式计数；双编码阶段逐个用户／最终回复文本块调用真实 `OfflineReportTokenizer`。

RSS 使用 Darwin [getrusage](https://github.com/apple/darwin-xnu/blob/main/bsd/man/man2/getrusage.2) 的 `ru_maxrss`，单位为字节。表中“前／后”都是**进程累计峰值**，包含测试框架、材料和准备；重复继承首次高水位，不能相减声称阶段内存增量。扫描子进程列为已回收子进程的 `RUSAGE_CHILDREN` 累计峰值，包含其每次加载整份合成 fixture；不与父峰值相加。调度准备的 RSS 还包含准备后的覆盖检查；阶段表 RSS 在后续规划覆盖检查前读取。

扫描走生产 `CodexDataSourceReader`、真实管道／JSON 解码及合成 `SyntheticCodexServer`，当前列表按每页 100 分页、归档列表为空，不访问真实 Codex。规划走 `ReportGenerationPlan`，本次三档均进入分批。受控调度走 `ReportBatchExecutor`；Adapter 再次计数每笔实际独立文本块、指令、原生结构格式及 1,024 token 预留，审计开销包括在调度时间内。返回空合成事实使已覆盖节点尽快成文，不评价语义或推断真实 AI 延迟／吞吐；计划层数是上界，不代表本样本实际执行了全部归并层。

沿用隔离沙盒，仅允许测试加载器及两个专用探针执行、仅临时目录可写、禁止真实主目录读取；性能模式额外禁止全部网络。测量不打开数据库。只保存聚合数字；原始 wire、正文或请求不进入本记录。

## 阶段样本

| 规模 | 阶段 | 并发 | 首次 ms | 重复 ms | 父累计峰值前 → 后（首次，字节） | 父累计峰值前 → 后（重复，字节） | 子累计峰值（首次／重复，字节） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small | scan | — | 59.756 | 49.087 | 46,989,312 → 50,593,792 | 50,610,176 → 50,692,096 | 11,173,888 / 11,173,888 |
| small | tokenize | — | 192.382 | 88.286 | 45,350,912 → 120,487,936 | 120,537,088 → 120,537,088 | — |
| small | plan | — | 791.244 | 670.499 | 45,400,064 → 140,361,728 | 140,492,800 → 141,819,904 | — |
| small | schedule | 1 | 175.190 | 184.350 | 140,558,336 → 141,737,984 | 141,737,984 → 141,737,984 | — |
| small | schedule | 3 | 173.231 | 173.551 | 139,935,744 → 141,819,904 | 141,819,904 → 142,426,112 | — |
| small | schedule | 8 | 170.128 | 190.026 | 139,673,600 → 142,622,720 | 142,622,720 → 142,802,944 | — |
| medium | scan | — | 467.822 | 456.064 | 76,087,296 → 98,598,912 | 98,615,296 → 101,335,040 | 39,731,200 / 39,731,200 |
| medium | tokenize | — | 897.703 | 824.125 | 61,587,456 → 137,150,464 | 137,183,232 → 137,723,904 | — |
| medium | plan | — | 12,083.417 | 11,927.740 | 61,587,456 → 352,190,464 | 356,548,608 → 381,616,128 | — |
| medium | schedule | 1 | 1,930.868 | 1,798.035 | 355,336,192 → 357,138,432 | 357,138,432 → 357,138,432 | — |
| medium | schedule | 3 | 1,764.288 | 1,728.984 | 353,959,936 → 356,794,368 | 356,794,368 → 356,794,368 | — |
| medium | schedule | 8 | 1,756.968 | 1,775.170 | 355,532,800 → 358,711,296 | 358,711,296 → 358,989,824 | — |
| large | scan | — | 8,969.881 | 8,884.105 | 441,679,872 → 659,079,168 | 659,079,168 → 659,079,168 | 456,572,928 / 456,671,232 |
| large | tokenize | — | 8,867.403 | 9,799.317 | 271,925,248 → 347,635,712 | 347,684,864 → 350,306,304 | — |
| large | plan | — | 78,668.808 | 75,988.587 | 271,892,480 → 2,333,605,888 | 2,333,605,888 → 2,478,653,440 | — |
| large | schedule | 1 | 17,796.609 | 17,814.270 | 2,334,638,080 → 2,334,638,080 | 2,334,638,080 → 2,334,638,080 | — |
| large | schedule | 3 | 17,712.732 | 17,836.514 | 2,333,392,896 → 2,333,392,896 | 2,333,392,896 → 2,333,392,896 | — |
| large | schedule | 8 | 17,836.622 | 17,727.609 | 2,333,638,656 → 2,333,638,656 | 2,333,638,656 → 2,333,638,656 | — |

每对各有一条首次和重复样本；未挑选最好值。原始精度、token 总量与计划上界见 [45 条聚合原始样本](offline-performance-samples.jsonl)。非调度行的并发设置不参与该阶段，原始 JSON 附带的 C／O／并发和零请求字段不能解释为该阶段发送了 AI 请求。

| 规模 | 双编码 token 总量（首次＝重复） | 规划请求上界 | 规划归并层上界 |
| --- | --- | --- | --- |
| small | 331,210 | 14 | 1 |
| medium | 3,307,051 | 161 | 3 |
| large | 32,952,093 | 1,360 | 4 |

## 调度准备样本

| 规模 | 并发 | 准备 ms | 父累计峰值前 → 后（字节） |
| --- | --- | --- | --- |
| small | 1 | 791.267 | 45,449,216 → 140,541,952 |
| small | 3 | 778.304 | 45,432,832 → 139,919,360 |
| small | 8 | 788.182 | 45,432,832 → 139,640,832 |
| medium | 1 | 12,303.593 | 61,734,912 → 355,319,808 |
| medium | 3 | 11,910.301 | 61,554,688 → 353,943,552 |
| medium | 8 | 11,796.563 | 61,505,536 → 355,516,416 |
| large | 1 | 75,883.609 | 271,908,864 → 2,334,638,080 |
| large | 3 | 76,257.807 | 271,958,016 → 2,333,392,896 |
| large | 8 | 75,895.439 | 271,990,784 → 2,333,638,656 |

## 硬约束

| 规模 | 并发 | 请求数（首次／重复） | 最大输入 token（首次／重复） | 实际在途峰值（首次／重复） |
| --- | --- | --- | --- | --- |
| small | 1 | 11 / 11 | 36,299 / 36,299 | 1 / 1 |
| small | 3 | 11 / 11 | 36,299 / 36,299 | 3 / 3 |
| small | 8 | 11 / 11 | 36,299 / 36,299 | 8 / 8 |
| medium | 1 | 121 / 121 | 39,303 / 39,303 | 1 / 1 |
| medium | 3 | 121 / 121 | 39,303 / 39,303 | 3 / 3 |
| medium | 8 | 121 / 121 | 39,303 / 39,303 | 8 / 8 |
| large | 1 | 1,021 / 1,021 | 39,303 / 39,303 | 1 / 1 |
| large | 3 | 1,021 / 1,021 | 39,303 / 39,303 | 3 / 3 |
| large | 8 | 1,021 / 1,021 | 39,303 / 39,303 | 8 / 8 |

三档故障注入各通过两种情况，原始聚合结果见 [故障／取消记录](offline-performance-checks.jsonl)。均使用请求屏障等待初始 3 笔提取，必要请求失败后其余 2 笔取消；取消场景故意让 Adapter 忽略取消并返回迟到成功，整个执行仍抛出取消。每种情况最终始终只有 3 笔请求，无后续提取、归并或成文，也无可返回的部分结果。

| 硬约束 | 实际证据 | 状态 |
| --- | --- | --- |
| 完整输入／Unicode | 三档真实 stdio 结果等于合成候选；规划按完整会话／轮次／片段重建，用户与 finalAnswer 的 UTF-8 逐字节相等；调度实际提取 ID 集合等于全部计划片段，根覆盖由真实 executor 检查 | 通过 |
| 单请求预算 | 每笔受控请求对真实独立文本块、指令及原生 schema 编码做双编码审计，含 1,024 预留；实测最大值见上表，均不超过 39,321 | 通过 |
| 并发／有限收敛 | 三档的 1／3／8 组首／重复在途峰值均受限；计划每层节点严格下降、引用有效；实际请求不超有限上界 | 通过 |
| 必要失败／取消／迟到结果 | 三档各一次 network 必要失败及取消后迟到成功，最终仅初始 3 笔、无部分返回 | 通过 |
| 原正文／来源的原子保护，密集归并及无缩减拒绝 | Debug／Release 全量隔离回归中的 `aNecessaryFailureOrCancellationStopsDispatchAndPreservesTheOldBody`、`cancellationRejectsLateSuccessAndFailureEvenWhenTheAdapterIgnoresCancellation`、`confirmedPlanProcessesEveryCharacterAndCreatesOneAtomicDraft`、`denseSummariesUseFiniteMergeLayersAndStopAsSoonAsTheyFit`、`anUnreducedMergeFailsWithoutAnotherLayerOrRepairRequest` 均通过；此行为证据来自统一流程回归，不由空事实压力样本推断 | 通过 |
| 原生操作可达性 | 未启动应用；布局回归不能代替原生键盘／滚动／指针及系统交互 | 未完成 |

## 最终 App 包体

| 范围 | 功能前对照 | 候选 | 增量 |
| --- | --- | --- | --- |
| 完整 .app 逻辑字节 | 3,041,091 | 16,849,331 | +13,808,240 |
| 完整 .app 磁盘占用字节 | 3,051,520 | 16,863,232 | +13,811,712 |
| 主可执行文件逻辑字节 | 3,039,536 | 16,845,792 | +13,806,256 |
| Contents/Resources 逻辑字节 | 0 | 1,951 | +1,951 |
| 包内其余文件逻辑字节 | 1,555 | 1,588 | +33 |

功能前：`123948dd8e3d7ffe8316ee9680b34898d811773c`；候选生产内容：`6f41f8a9e60d3c1356b0afec274734766114a30e`。对照是起点祖先，树中没有日报／Codex／tokenizer 生产文件。本票没有修改生产源码、资源或 Xcode 工程；因此候选归档准确代表本票最终生产内容，排除了工作区无关排序改动。

两个提交均由 `git archive` 提取到 `.build/acceptance-35/package-comparison/{base,candidate}-source`，各用新建的 derived data 目录。候选的 `.build/cargo`／`.build/rustup` 只链接到既有固定工具链缓存，不改变归档源码。两次命令均成功退出 0：

```bash
for variant in base candidate; do
  rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project ".build/acceptance-35/package-comparison/$variant-source/random-thoughts.xcodeproj" \
    -scheme random-thoughts -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ".build/acceptance-35/package-comparison/$variant-derived" \
    -clonedSourcePackagesDirPath .build/acceptance-35/package-comparison/packages \
    CODE_SIGNING_ALLOWED=NO build
done
rtk proxy /usr/bin/python3 script/measure-app-size.py \
  .build/acceptance-35/package-comparison/base-derived/Build/Products/Release/random-thoughts.app \
  .build/acceptance-35/package-comparison/candidate-derived/Build/Products/Release/random-thoughts.app
```

测的是两个完整 arm64 Release `.app`，不包含包外 `.app.dSYM`、构建中间产物、测试或压力夹具。逻辑字节为包内文件及符号链接自身大小之和（不含目录元数据、不跟随目录链接）；磁盘占用为 `du -sk` × 1024，另直接复核为 2,980／16,468 KiB。两主可执行文件均由 `file` 确认为 arm64 Mach-O。

主可执行文件 SHA-256：对照 `cd1c145f7e9e9f9cf6001c62bcd98fb126e9d1ae102d42741a8ad9aae21a9996`；候选 `352e00f0151d14d95bf2047df6d49b6a3ee0a955b8613be6b4e650a1bc6e8b30`。

完整 App 逻辑增量 **13,808,240 字节（约 13.169MiB）**，磁盘增量 **13,811,712 字节**。这是日报功能前后完整包的差值，未使用词表尺寸或本轮离线文件的零增量替代。没有性能数字门槛；两包纯构建及包体记录通过，不构成签名／公证／生产分发验收。

## 命令与最终回归

| 实际命令 | 结果与证据 |
| --- | --- |
| `rtk proxy ./script/test-isolated.sh --configuration Debug --filter ReportAcceptanceMaterialTests`（最终） | 1 套件、4 项通过，含真实 stdio 合成 wire 回归。 |
| `rtk proxy ./script/measure-report-performance.sh`（阶段矩阵） | 成功退出 0；运行目录 `.build/acceptance-35/run-20261029T190846Z.umhr5z`。执行 scan／tokenize／plan，以及并发 1／3／8 的 schedule；共 36 条首次／重复阶段样本与 9 条调度准备样本。当时脚本尚未接入 constraints，随后单独补测。 |
| `rtk proxy ./script/measure-report-performance.sh all constraints` | 成功退出 0；运行目录 `.build/acceptance-35/run-20261029T192248Z.RTAkqL`。三档各执行必要失败及取消后迟到成功，共 3 条聚合检查。最终脚本默认一次运行包含上述阶段和 constraints。 |
| `rtk proxy ./script/build.sh --configuration Debug` | `BUILD SUCCEEDED`，只构建生产应用；功能前及候选 Release 纯构建命令与结果见上节。 |
| `rtk proxy ./script/test-isolated.sh --configuration Debug` | 55 套件、272 项登记；2 个显式压力入口按设计跳过，其余 270 项执行通过，退出 0。 |
| `rtk proxy ./script/test-isolated.sh --configuration Release` | 55 套件、272 项登记；相同 2 项跳过，其余 270 项执行通过，退出 0。压力入口由上两条测量命令实际执行。 |
| `rtk proxy bash -n script/measure-report-performance.sh script/test-isolated.sh` | 通过。 |
| `rtk proxy git diff --cached --check 6f41f8a` | 通过；暂存内容仅含本票文件，无既有工程排序变化。 |

原始运行日志留在各运行目录，只有聚合 JSONL 随本记录提交。全部 45 条样本的规模、唯一组合、字节、正耗时、累计峰值、预算／请求／并发界限已复核；3 条故障记录均通过。纯构建只有既有 Xcode CoreDevice／CoreSimulator 环境诊断及 AppIntents 元数据跳过提示，没有 Swift 代码警告。未将环境诊断算作代码通过证据，也未改动相关环境。

提交前对 `git diff --cached 6f41f8a` 进行两轴独立 code-review：Standards 为 0 项文档标准违规、0 项可行动代码气味；Spec 为 0 项可行动问题。评审核对生产调用方、实际聚合输出及包体比较结果；没有启动应用或重复长时压力测量。

## 失败、修正与未完成

- 合成 wire 回归先实际执行并因空扫描结果失败，随后接入公开 wire 转换；第二次暴露材料标题尾空格会被生产扫描器规范化，修正合成标题后 4 项材料测试通过，压力正文的字节定义不变。
- 初次接线有编译失败：误用六章节解析接口、遗漏 `await`；修正为真实 `ReportPayload.render`。Release 整模块编译还暴露协议直接遵守触发的 actor isolation 推导错误，按既有替身模式把遵守声明放入扩展。以上不是行为红绿证据。
- 首轮小档双编码命令在编译阶段失败，没有性能样本；随后整矩阵命令因沙盒相对导入无法解析退出，也没有性能样本。已删除新建的无效导入配置，在现有 profile 中用显式参数控制回环例外，性能模式关闭全部网络后重新运行；没有无沙盒重跑。
- 真实 Codex／AI、macOS 26.5 和当前系统原生交互、快捷键／Dock／登录／显示器／睡眠、可达性／截图、真实 OSLog 落盘与 #36 的 48 任务均未实测，保持未完成。没有借离线结果声明 #35 或父 #20 整体验收通过。
