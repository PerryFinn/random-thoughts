# 构建与隔离测试

本入口承接 [#21](https://github.com/PerryFinn/random-thoughts/issues/21) 至 [#29](https://github.com/PerryFinn/random-thoughts/issues/29) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20) 的测试隔离要求。生产构建、隔离 U/I/L、会启动应用的系统/UI 验收分别执行。#28 的直接生成、真实离线 tokenizer 与协议假服务边界见 [chat-completions-generation.md](chat-completions-generation.md)，#29 的原生 output／SSE、配置与共享流程边界见 [responses-generation.md](responses-generation.md)。

## 命令

在仓库根目录运行：

```bash
./script/build.sh
./script/test-isolated.sh
./script/test-isolated.sh --filter IntelligenceIsolationTests
```

`build.sh` 仅调用 Xcode 的 `build`，产物位于 `.build/DerivedData`，不运行旧启动脚本，也不终止已运行的应用。隔离入口先用 SwiftPM 编译测试，再在 macOS 沙盒内执行 Swift Testing 测试程序；支持 Swift Testing 的 `--filter` 参数。它没有应用可执行产品、生产 `TEST_HOST` 或生产入口初始化。

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
