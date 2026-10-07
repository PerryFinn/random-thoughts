# 日报本机遥测：日志库选型证据

> 调查日期：2026-10-07
>
> 状态：[确定验收、测试与隐私遥测矩阵](https://github.com/PerryFinn/random-thoughts/issues/19)的选型证据。用户已在 Q8 确定采用 CocoaLumberjack 的 OSLog 后端，并于 2026-10-07 确认完整方案及文档发布；不代表依赖已经接入或日报遥测已经实现。
>
> 方法：只读官方文档、项目 README、发布记录及固定版本源码；未安装依赖、运行应用或测试，未访问私有会话、凭据或真实 AI 服务。Apple Logger/OSLog、swift-log 与桥接库证据由主 Agent 核查后合并。

## 用户已确定的路线与研究结论

本票已确认的范围是最小本机日志，不上传遥测。**用户已确定采用 CocoaLumberjack，通过 DDOSLogger 写系统 OSLog，保留业务白名单与内存测试边界。** 类型化入口只负责限制允许的事件和字段，再交给该日志库；不自行实现日志存储、轮转、队列或上传，也不注册文件或网络 logger。其他库的材料保留为选型比较证据。

现有 `random-thoughts/Support/AppTelemetry.swift` 已直接使用 OSLog，为 Windowing、MenuBar、Refresh、Proximity 建立四个 Logger；当前不是自研日志引擎。Apple 提供 subsystem/category、日志等级与隐私插值，官方建议日志优先使用固定字符串和自定义数字。[Apple 日志指南](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)、[OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy)

**选库不能替代业务白名单。** 即使使用 `.private`、字段遮盖或本机数据库，也不能把聊天正文、生成偏好、来源、端点、凭据或敏感路径送入日志后，宣称已经满足“这些数据不进入遥测”。禁记内容应在构造事件时排除；库的输出与过滤机制只是第二层边界。

## 维护与平台快照

以下是调查当天 GitHub 最新正式发布记录；发布活跃不代表已经验证本项目的构建、性能或隐私适配。

| 方案 | 已核查维护／平台证据 |
| --- | --- |
| Apple Logger/OSLog | macOS 原生统一日志；本仓库已经使用。系统 API，无需新增第三方日志包。[Apple 指南](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) |
| apple/swift-log | 官方日志 API 包，生产使用需选择合适后端；核查源码为 2026-10-02 的 `c29472f`。可替换的 `LogHandler` 是已公开扩展点。[README](https://github.com/apple/swift-log/blob/c29472f01064bb4b38de12b5b57a98b1b290e7e3/README.md)、[LogHandler](https://github.com/apple/swift-log/blob/c29472f01064bb4b38de12b5b57a98b1b290e7e3/Sources/Logging/LogHandler.swift#L125-L138) |
| CocoaLumberjack | 最新正式版 3.10.0，2026-09-21 发布。默认 Package.swift 为 Swift tools 6.4，但同一 tag 另有 tools 6.1、6.2、6.3 的版本化 manifest，均声明 macOS 12、Swift 6 语言模式；不能将 6.4 写成所有工具链的统一最低要求。README 的旧平台信息不能代替具体版本 manifest。[发布](https://github.com/CocoaLumberjack/CocoaLumberjack/releases/tag/3.10.0)、[默认 manifest](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Package.swift#L1-L40)、[6.1](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Package%40swift-6.1.swift#L1-L21)、[6.2](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Package%40swift-6.2.swift#L1-L24)、[6.3](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Package%40swift-6.3.swift#L1-L26) |
| Pulse | 最新正式版 5.2.3，2026-06-10 发布。该版 manifest 为 Swift tools 5.10、macOS 13；README 的 Pulse 5.0 平台表写 macOS 12，不能代替具体版本 manifest。SDK、SwiftUI 检查界面与独立 Pulse Mac 查看应用是不同组件。[发布](https://github.com/kean/Pulse/releases/tag/5.2.3)、[Package.swift](https://github.com/kean/Pulse/blob/5.2.3/Package.swift#L1-L30)、[组件说明](https://github.com/kean/Pulse/blob/5.2.3/README.md#L6-L30) |
| OpenTelemetry Swift | SDK/exporter 仓库最新正式版 2.5.1，2026-08-06 发布；core 同版 2026-07-02 发布。两者要求 Swift tools 6.0；扩展包 macOS 12，core macOS 10.13。官网将 traces 标为 Stable、logs/metrics 标为 Development；2.5.1 README 对 logs 写 beta，不能统称全部信号稳定。[发布](https://github.com/open-telemetry/opentelemetry-swift/releases/tag/2.5.1)、[core 发布](https://github.com/open-telemetry/opentelemetry-swift-core/releases/tag/2.5.1)、[扩展 manifest](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Package.swift#L1-L39)、[core manifest](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Package.swift#L1-L25)、[官网状态](https://opentelemetry.io/docs/languages/swift/#status-and-releases)、[版本 README](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/README.md#L73-L99) |

本机工具链只读核查使用仓库默认 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`：`xcodebuild -version` 返回 Xcode 26.6（17F113），`xcrun swift --version` 返回 Apple Swift 6.3.3（swiftlang-6.3.3.1.3，arm64-apple-macosx26.0）。因此 3.10.0 存在与本机 Swift 6.3 对应且最低平台低于本项目 macOS 26.5 的 manifest；这里只确认声明与工具链版本，未解析依赖或验证实际编译。

## 日志目的地、隐私风险与测试边界

### Apple Logger/OSLog 与 swift-log

原生 Logger 把消息交给系统统一日志，可在 Console 或系统日志工具按 subsystem/category 检索；它不是应用自建文件库。系统决定日志保存行为，不能把使用 OSLog 表述为“完全不落盘”或“可由应用擦除全部系统日志”。字段隐私插值不能替代禁记规则。[Apple 日志指南](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)、[OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy)

swift-log 提供 API 与可替换 handler；最终是否写系统日志、文件或网络由所接后端决定，使用 API 包本身不能证明目标边界。可用内存 handler 检查输出，这是扩展点提供的测试方式，不是业务白名单已实现的证据。[swift-log README](https://github.com/apple/swift-log/blob/c29472f01064bb4b38de12b5b57a98b1b290e7e3/README.md)、[LogHandler](https://github.com/apple/swift-log/blob/c29472f01064bb4b38de12b5b57a98b1b290e7e3/Sources/Logging/LogHandler.swift#L125-L138)

已核查的第三方 `swift-log-oslog` 桥接库主分支最后提交为 2022-02-20 的 `1b2cb12`。未归档不等于不能用，但该实现将消息和全部 metadata 拼成一个字符串，以 `%{public}@` 写 OSLog，不能继承原生字段级 `OSLogPrivacy`；不能仅因后端名称有 OSLog 就声称等价隐私语义。[桥接源码](https://github.com/chrisaljoudi/swift-log-oslog/blob/1b2cb12c3ec2cdc171e1673a488dec1d40a69158/Sources/LoggingOSLog/LoggingOSLog.swift#L21-L35)

### CocoaLumberjack

- **目的地与副本：** `DDLog` 初始化的 logger 列表为空，由应用显式注册目的地。`DDOSLogger` 对接系统 `os_log`；注册 `DDFileLogger` 才增加应用日志文件。README 声明框架默认不自行收集数据，不应因它支持自定义网络 logger 就断言默认上传。README 入门示例同时注册 OSLog 和文件 logger，照抄示例会增加文件副本。[DDLog 初始化](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDLog.m#L160-L197)、[注册示例](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/README.md#L73-L91)、[数据实践](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/README.md#L230-L269)
- **隐私：** 3.10.0 的 `DDOSLogger` 将格式化后的完整字符串以 `%{public}s` 写入系统日志，不能保留原生逐字段的隐私插值。它接收任意日志文本；业务若传入正文、错误对象或端点，这些值可以进入输出。此库不自行自动抓取 AI 网络正文，风险来自传给它的消息及已注册的目的地。[DDOSLogger](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDOSLogger.m#L142-L155)
- **分类与默认元数据：** `DDOSLogger(subsystem:category:)` 可显式设定固定 subsystem/category，两者应同时非空；共享默认实例使用 `OS_LOG_DEFAULT`。未设置 formatter 时只输出 `DDLogMessage.message`，不会自动拼接源码路径、函数名或 tag。不过 Swift 便捷函数默认把 `#file`、`#function`、`#line` 放入日志对象，tag 默认为 nil；这些字段由 `DDLogMessage` 单独保存。因此业务入口还需显式使用固定非敏感 file/function 标记、line=0、tag=nil，不以“没有输出”替代“没有进入遥测对象”。[初始化契约](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/include/CocoaLumberjack/DDOSLogger.h#L70-L101)、[OSLog 输出](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDOSLogger.m#L125-L155)、[Swift 默认参数与实例注入](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjackSwift/CocoaLumberjack.swift#L61-L103)、[消息字段存储](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDLog.m#L929-L966)
- **测试与异步完成：** 可向独立 `DDLog` 实例注册内存 `DDLogger`，并通过 Swift API 的 `ddlog` 参数注入，避免测试改动全局共享 logger 列表或全局日志等级。待测试生产者完成提交后，在 logging/logger queue 之外调用该实例 `flushLog()`：实现以 `dispatch_sync` 排入 logging queue，并以 `dispatch_group_wait` 等待 logger flush，源码明确此前提交的日志已执行；随后读取线程安全捕获结果，无需任意 sleep。这不保证 OSLog 已持久化，也不能等待尚未入队的并发生产者。自定义 logger 若自行异步缓冲，需正确实现其 flush 契约。[Swift 注入](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjackSwift/CocoaLumberjack.swift#L61-L103)、[实例 flush](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDLog.m#L453-L464)、[执行与等待](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/DDLog.m#L738-L814)、[DDLogger 协议](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Sources/CocoaLumberjack/include/CocoaLumberjack/DDLog.h#L588-L659)、[官方测试替身](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.10.0/Tests/CocoaLumberjackTests/DDLogTests.m#L19-L44)

### Pulse

- **目的地与副本：** `LoggerStore.shared` 创建 `current.pulse` 本机持久库，保存消息、网络请求及正文 blob；常规记录默认不是 OSLog 输出。`storeMessage` 接受任意字符串与 metadata；集成 URLSession proxy 或手动接入 NetworkLogger 后，可收集请求和响应正文并保存副本。[默认库](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/LoggerStore/LoggerStore.swift#L63-L103)、[消息与正文写入](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/LoggerStore/LoggerStore.swift#L288-L311)、[blob 写入](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/LoggerStore/LoggerStore.swift#L410-L432)、[系统日志边界](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/Pulse.docc/Articles/NetworkLogging-Article.md#L112-L156)
- **隐私：** 默认 `sensitiveHeaders`、`sensitiveQueryItems`、`sensitiveDataFields` 都为空；可配置遮盖 header/query/JSON 字段或过滤事件，但这不是日报业务的禁记白名单，也不保证识别正文内所有秘密。官方特别提醒手动遮盖请求／响应时还应处理 metrics 内的请求／响应副本。[过滤默认值](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/NetworkLogger/NetworkLogger.swift#L81-L108)、[正文捕获](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/NetworkLogger/NetworkLogger.swift#L245-L268)、[metrics 提醒](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/Pulse.docc/Articles/NetworkLogging-Article.md#L130-L152)
- **远程行为：** RemoteLogger 的首次默认 `isEnabled` 和 `isAutomaticConnectionEnabled` 均为 false；显式启用后可连接 Pulse Mac 应用，已启用状态会由 AppStorage 保留。因此不能说默认云端上传，也不能说永远不会离开设备。仅导入库不等于已开启全局抓包。[RemoteLogger 默认值与启用](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/RemoteLogger/RemoteLogger.swift#L31-L35)、[连接与恢复](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/RemoteLogger/RemoteLogger.swift#L107-L147)、[显式网络接入](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/Pulse.docc/Articles/GettingStarted.md#L21-L47)
- **测试与适用性：** 支持注入自定义 LoggerStore、`.inMemory` 无磁盘选项及事件过滤。适合需要网络检查器、正文调试和共享诊断包的开发流程；其默认内容留存与本票“最小日志、正文不入遥测”的目的不同。若采用，必须额外限制 store、network capture 和 remote logging，不能只配置凭据遮盖。[内存库与过滤](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/LoggerStore/LoggerStore%2BConfiguration.swift#L43-L48)、[事件过滤与保留](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/LoggerStore/LoggerStore%2BConfiguration.swift#L86-L114)、[store 注入](https://github.com/kean/Pulse/blob/5.2.3/Sources/Pulse/NetworkLogger/NetworkLogger.swift#L111-L127)

### OpenTelemetry Swift

- **目的地与副本：** 默认 API logger 使用 no-op builder，SDK LoggerProviderBuilder 的 processor 列表默认为空；只引入 API／SDK不等于自动上传。显式安装 OTLP exporter 并交给 processor 后会发送记录；HTTP log exporter 的默认地址是 localhost:4318。可选 PersistenceLogExporterDecorator 会增加磁盘持久副本与后续导出，不是默认启用。[默认 API](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Sources/OpenTelemetryApi/Logs/DefaultLogger.swift#L8-L38)、[SDK builder](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Sources/OpenTelemetrySdk/Logs/LoggerProviderBuilder.swift#L8-L37)、[HTTP exporter](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Exporters/OpenTelemetryProtocolHttp/logs/OtlpHttpLogExporter.swift#L15-L31)、[导出发送](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Exporters/OpenTelemetryProtocolHttp/logs/OtlpHttpLogExporter.swift#L56-L85)、[持久装饰器](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Exporters/Persistence/PersistenceLogExporterDecorator.swift#L9-L46)
- **OSLog 与隐私：** SignPostIntegration 是把 span 的 begin/end 映射到系统性能标记，不是将全部 logs 自动送入 Apple Logger 的后端。日志 SDK允许任意 body 和属性。API 自身另有默认写 OSLog 的反馈消息处理器；不能把 no-op 业务记录理解为完全没有系统诊断输出。[SignPost 说明](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Instrumentation/SignPostIntegration/README.md#L1-L20)、[日志 body／attributes](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Sources/OpenTelemetrySdk/Logs/LogRecordBuilderSdk.swift#L53-L87)、[feedback handler](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Sources/OpenTelemetryApi/OpenTelemetry.swift#L41-L62)
- **网络风险：** URLSessionInstrumentation 需要显式初始化；安装后默认覆盖全部请求并允许注入追踪头。delegate payload 收集的默认值是 false，不能断言默认保存全部网络正文；但默认 span 属性包含完整 URL、路径、主机，定制回调也可访问请求或响应内容，这已与禁记完整端点的范围有冲突。[配置默认值](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Instrumentation/URLSession/URLSessionInstrumentationConfiguration.swift#L26-L91)、[URL 属性](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Sources/Instrumentation/URLSession/URLSessionLogger.swift#L66-L106)
- **测试与适用性：** SDK 有 InMemoryLogRecordExporter，可取回完成记录、清除并关闭，不必启动 collector。适合将来明确需要 logs/traces/metrics 关联和标准 exporter 的范围；当前无上传、少量本机事件并不需要这些组件。扩展包还声明 NIO、gRPC、protobuf 等依赖，实际成本随所选产品而异，本研究没有测量体积或运行开销。[内存 exporter](https://github.com/open-telemetry/opentelemetry-swift-core/blob/2.5.1/Sources/OpenTelemetrySdk/Logs/Export/InMemoryLogRecordExporter.swift#L8-L43)、[扩展依赖](https://github.com/open-telemetry/opentelemetry-swift/blob/2.5.1/Package.swift#L32-L39)

## Q8 已确定路线的实施与验收边界

1. 采用 CocoaLumberjack 的 DDOSLogger；生产只注册这一系统日志目的地，使用固定 subsystem/category，不增加 DDFileLogger、网络 logger、自动抓包或上传。
2. 类型化业务入口只接受白名单事件和非敏感字段，不向通用消息 API 传递正文、原始错误对象、完整端点或任意 metadata；DDOSLogger 的整个字符串为 public，不能依赖字段隐私插值来兜底。
3. 验收合成敏感标记不会进入最终消息及捕获对象的 file/function/tag 等字段；以独立 DDLog、内存 DDLogger 和生产者完成后显式 flush 检查异步记录，不通过 sleep 猜测完成时机。这是待实现的验收要求，不是已通过测试的声明。
4. Apple Logger、swift-log、Pulse 与 OpenTelemetry 的比较解释了各自能力和附加数据路径；库选型现已由用户确定，本文不改变已确认的其他验收决策，也不新增应用日志文件或上传许可。系统 OSLog 自身可能保存日志，不承诺完全不落盘或能由应用清除全部记录。

未验证：本项目接入这些依赖后的编译兼容性、二进制体积、内存与延迟、库全部辅助诊断路径、系统日志保留时间，以及未来版本行为。以上是选型证据，不是完整 SDK 安全审计或实际集成验证。
