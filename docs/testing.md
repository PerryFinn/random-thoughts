# 构建与隔离测试

本入口承接 [#21](https://github.com/PerryFinn/random-thoughts/issues/21) 至 [#25](https://github.com/PerryFinn/random-thoughts/issues/25) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20) 的测试隔离要求。生产构建、隔离 U/I/L、会启动应用的系统/UI 验收分别执行。

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

SwiftPM 的 `random_thoughts` 库直接编译清单列出的生产 Swift 文件，Xcode 应用继续编译这些文件，业务实现不复制。清单只纳入可隔离实现；生产 `@main`、应用 Delegate、AppKit 窗口操作、蓝牙及系统操作 Adapter 不在测试产物中。`DailyReportFlow` 的动作／状态接口供日报界面和主要业务测试共用；窗口系统动作注入受控接收器，原生内容通过 `NSHostingView` 测量且不创建窗口。#23 接入内存草稿与真实 SQLite，扫描和生成由后续票接入。窗口及内容边界详见 [daily-report-windows.md](daily-report-windows.md) 与 [daily-report-content.md](daily-report-content.md)。

模型刷新作为既有行为的验证样本：Store 显式接收服务、UserDefaults、时钟和调度，服务显式接收 URLSession。只有生产组合传入真实会话及系统时间，测试组合使用合成传输和受控时间。构造 Store 不启动刷新；受控调度用明确屏障推进，失败保留旧状态且不改用生产依赖。

## 运行环境及隔离证据

- 每次运行建立独立临时根目录；每个测试环境再分配独立目录、数据库位置、合成测试密钥和随机 UserDefaults suite。`defer` 清理 suite 与目录，脚本退出再清理整次运行目录；不删除或重置用户数据库。
- 固定时钟与可控调度器可供后续日报模块注入。用完成/调度屏障等待，不通过任意 sleep、真实聚焦、用户凭据或 Codex 数据建立前提。
- 数据库重开测试先等待 `DailyReportDatabase.close()` 归还连接与目录锁，不依赖异步任务中 ARC 临时引用的释放时机；生产组合仍持有应用生命周期内的唯一连接。
- 合成 URLProtocol 仅安装到测试专用的 ephemeral URLSession，禁缓存/凭据/Cookie 存储。未知请求或注入故障直接失败，不回退 `URLSession.shared`。
- 执行沙盒禁止网络、未列入白名单的进程执行、蓝牙服务访问以及真实用户主目录内容读取；主目录内仅放行仓库读取，系统框架正常读取。所有文件及偏好写入独立临时位置。脚本要求系统沙盒可用，任何准备或沙盒失败均非零退出，不提供无隔离重跑分支。
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
