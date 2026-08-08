# 仓库指南

## 项目结构与模块组织

`random-thoughts/` 包含 SwiftUI 菜单栏应用。代码按职责划分：`App/` 存放应用入口，`Models/` 定义解码数据，`Services/` 负责网络访问，`Stores/` 管理可观察状态，`Views/` 包含界面组件，`Support/` 提供 AppKit 桥接和遥测支持。图片与颜色应添加到 `Assets.xcassets`，应用元数据位于 `Config/Info.plist`。单元测试存放在 `random-thoughtsTests/`，启动与交互测试存放在 `random-thoughtsUITests/`。`.build/` 和 `DerivedData/` 均为生成目录，不应提交。

## 构建、测试与开发命令

- `./script/build_and_run.sh run`：构建 Debug 应用到 `.build/DerivedData` 并启动。
- `./script/build_and_run.sh verify`：构建并启动应用，然后确认进程仍在运行。
- `./script/build_and_run.sh logs`：输出进程日志；使用 `telemetry` 过滤应用遥测，或使用 `debug` 在 LLDB 下启动。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project random-thoughts.xcodeproj -scheme random-thoughts -destination 'platform=macOS' test`：运行单元测试和 UI 测试。

使用 Xcode 打开 `random-thoughts.xcodeproj` 可进行预览和交互式调试。项目最低支持 macOS 26.5。

## 编码风格与命名约定

遵循标准 Swift 和 SwiftUI 规范，使用四空格缩进。类型与文件名采用 `UpperCamelCase`，属性和函数采用 `lowerCamelCase`，名称应清楚表达行为，例如 `fetch()` 和 `comparisonWithNextLowerEffort`。保持视图职责单一，将网络请求和状态转换放入服务或 Store。涉及 UI 的测试与 API 使用 `@MainActor`；并发代码应保留明确的 `Sendable` 边界。项目未配置格式化器或 Linter，请使用 Xcode 格式化并保持编译无警告。

## UI 交互规范

可点击控件应采用与网页一致的鼠标反馈：启用状态的 `Button`、`Toggle` 等交互控件使用 `.pointerStyle(.link)`，让鼠标悬停时显示小手；禁用状态使用 `.pointerStyle(.default)`，避免暗示控件仍可点击。应将指针样式添加到具体控件，而不是外层容器，防止普通文本或空白区域错误显示小手。

## 测试指南

单元与布局测试使用 Swift Testing（`@Test`、`#expect`、`#require`），UI 自动化使用 XCTest。测试名应描述具体行为，例如 `limitsTrackedPointsToConfiguredMaximum`。持久化测试应使用独立的 `UserDefaults` suite，并在 `defer` 中清理。数据解码、Store 逻辑和固定布局尺寸的修改都应补充回归测试。提交评审前运行完整测试命令；UI 测试需要活跃的 macOS 图形会话。

## 提交与拉取请求指南

现有历史偏好简短、祈使式的提交主题，部分提交使用 Conventional Commits 前缀，如 `feat:`。建议保持提交聚焦，例如 `fix: preserve selection limit` 或 `test: cover stale cache decoding`。拉取请求应说明用户可见的变化、列出测试结果、关联相关 Issue，并为菜单面板或“设置”界面变更提供截图。远程数据协议、`Info.plist` 或最低系统版本的改动必须明确标注。
