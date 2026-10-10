# 构建与隔离测试

本入口承接 [#21](https://github.com/PerryFinn/random-thoughts/issues/21)、[#22](https://github.com/PerryFinn/random-thoughts/issues/22) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20) 的测试隔离要求。生产构建、隔离 U/I/L、会启动应用的系统/UI 验收分别执行。

## 命令

在仓库根目录运行：

```bash
./script/build.sh
./script/test-isolated.sh
./script/test-isolated.sh --filter IntelligenceIsolationTests
```

`build.sh` 仅调用 Xcode 的 `build`，产物位于 `.build/DerivedData`，不运行旧启动脚本，也不终止已运行的应用。隔离入口先用 SwiftPM 编译测试，再在 macOS 沙盒内执行 Swift Testing 测试程序；支持 Swift Testing 的 `--filter` 参数。它没有应用可执行产品、生产 `TEST_HOST` 或生产入口初始化。

macOS 的 `.xctest` 是加载包，脚本用当前工具链的 `swiftpm-testing-helper` 加载它，调用方式依据 [Swift Testing 官方说明](https://github.com/swiftlang/swift-testing/blob/main/Documentation/CommandlineDebugging.md)。沙盒仅允许执行这个加载器。

旧 Xcode 测试目标仍包含真实窗口聚焦等系统测试，必须单独获得应用启动授权：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -scheme random-thoughts \
  -destination 'platform=macOS' test
```

此命令会启动应用及 UI 测试，不能用作隔离验证。`build_and_run.sh` 的各模式同样属于应用启动操作。

## 复用实现与外部边界

SwiftPM 的 `random_thoughts` 库直接编译清单列出的生产 Swift 文件，Xcode 应用继续编译这些文件，业务实现不复制。清单只纳入可隔离实现；生产 `@main`、应用 Delegate、AppKit 窗口操作、蓝牙及系统操作 Adapter 不在测试产物中。`DailyReportFlow` 的动作／状态接口供日报界面和主要业务测试共用；窗口系统动作注入受控接收器，原生内容通过 `NSHostingView` 测量且不创建窗口。扫描、草稿、生成和数据库由后续票接入。窗口边界详见 [daily-report-windows.md](daily-report-windows.md)。

模型刷新作为既有行为的验证样本：Store 显式接收服务、UserDefaults、时钟和调度，服务显式接收 URLSession。只有生产组合传入真实会话及系统时间，测试组合使用合成传输和受控时间。构造 Store 不启动刷新；受控调度用明确屏障推进，失败保留旧状态且不改用生产依赖。

## 运行环境及隔离证据

- 每次运行建立独立临时根目录；每个测试环境再分配独立目录、数据库位置、合成测试密钥和随机 UserDefaults suite。`defer` 清理 suite 与目录，脚本退出再清理整次运行目录；不删除或重置用户数据库。
- 固定时钟与可控调度器可供后续日报模块注入。用完成/调度屏障等待，不通过任意 sleep、真实聚焦、用户凭据或 Codex 数据建立前提。
- 合成 URLProtocol 仅安装到测试专用的 ephemeral URLSession，禁缓存/凭据/Cookie 存储。未知请求或注入故障直接失败，不回退 `URLSession.shared`。
- 执行沙盒禁止网络、额外进程执行、蓝牙服务访问以及真实用户主目录内容读取；主目录内仅放行仓库读取，系统框架正常读取。所有文件及偏好写入独立临时位置。脚本要求系统沙盒可用，任何准备或沙盒失败均非零退出，不提供无隔离重跑分支。
- U 验证既有刷新状态与固定时间；I 验证真实请求构造/解码、受控失败和沙盒禁止能力；L 通过 `NSHostingView.fittingSize` 测量生产卡片，不创建、展示或聚焦窗口。

日报遥测测试直接使用固定版本 CocoaLumberjack，在独立 `DDLog` 中注册线程安全内存 logger；生产者完成提交后在日志队列外 `flushLog()`，检查完整 `DDLogMessage` 及最终文本。生产注册测试检查唯一 `DDOSLogger` 与无 formatter，固定 subsystem/category 由源码核对，不发系统日志事件。真实聚焦、Dock、快捷键与睡眠／唤醒交互由授权的 #35 验收承接。

这一入口不代表 SQLite/CryptoKit、tokenizer、真实 Codex/AI、系统交互或整个日报功能已经验收。后续各票补充其真实机制和行为测试，并记录实际执行的命令、结果及未执行项目。

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
