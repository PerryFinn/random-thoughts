# 构建与隔离测试

本入口承接 [#21](https://github.com/PerryFinn/random-thoughts/issues/21) 和父规格 [#20](https://github.com/PerryFinn/random-thoughts/issues/20) 的测试隔离要求。生产构建、隔离 U/I/L、会启动应用的系统/UI 验收分别执行。

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

SwiftPM 的 `random_thoughts` 库直接编译清单列出的生产 Swift 文件，Xcode 应用继续编译这些文件，业务实现不复制。清单只纳入可隔离实现；生产 `@main`、生命周期、蓝牙及系统操作 Adapter 不在测试产物中。后续日报流程实现加入同一库，日报窗口和主要业务测试共用父规格已确认的动作/状态接口，真实 Adapter 另做集成；本票不预建扫描、生成、数据库或日报窗口功能。

模型刷新作为既有行为的验证样本：Store 显式接收服务、UserDefaults、时钟和调度，服务显式接收 URLSession。只有生产组合传入真实会话及系统时间，测试组合使用合成传输和受控时间。构造 Store 不启动刷新；受控调度用明确屏障推进，失败保留旧状态且不改用生产依赖。

## 运行环境及隔离证据

- 每次运行建立独立临时根目录；每个测试环境再分配独立目录、数据库位置、合成测试密钥和随机 UserDefaults suite。`defer` 清理 suite 与目录，脚本退出再清理整次运行目录；不删除或重置用户数据库。
- 固定时钟与可控调度器可供后续日报模块注入。用完成/调度屏障等待，不通过任意 sleep、真实聚焦、用户凭据或 Codex 数据建立前提。
- 合成 URLProtocol 仅安装到测试专用的 ephemeral URLSession，禁缓存/凭据/Cookie 存储。未知请求或注入故障直接失败，不回退 `URLSession.shared`。
- 执行沙盒禁止网络、额外进程执行、蓝牙服务访问以及真实用户主目录内容读取；主目录内仅放行仓库读取，系统框架正常读取。所有文件及偏好写入独立临时位置。脚本要求系统沙盒可用，任何准备或沙盒失败均非零退出，不提供无隔离重跑分支。
- U 验证既有刷新状态与固定时间；I 验证真实请求构造/解码、受控失败和沙盒禁止能力；L 通过 `NSHostingView.fittingSize` 测量生产卡片，不创建、展示或聚焦窗口。

这一入口不代表 SQLite/CryptoKit、tokenizer、CocoaLumberjack、真实 Codex/AI、系统交互或整个日报功能已经验收。后续各票补充其真实机制和行为测试，并记录实际执行的命令、结果及未执行项目。

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
