# 构建与隔离测试

## 命令

在仓库根目录运行以下命令。

```bash
./script/build.sh --configuration Debug
./script/build.sh --configuration Release
./script/test-isolated.sh --configuration Debug
./script/test-isolated.sh --configuration Release
./script/test-isolated.sh --filter IntelligenceIsolationTests
```

`build.sh` 调用 Xcode 纯构建，产物位于 `.build/DerivedData`。`test-isolated.sh` 使用 SwiftPM 的 `swiftbuild` 构建系统编译测试，再通过 `swiftpm-testing-helper` 在 macOS 沙盒内加载 `IsolatedTests.xctest`。隔离测试默认使用 Debug，接受 Swift Testing 的 `--filter` 参数。隔离构建使用 `-enable-testing` 支持 `@testable`，Release 保持优化。

如需检查旧宿主和 UI 测试能否编译，使用以下命令。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project random-thoughts.xcodeproj -scheme random-thoughts \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

执行旧宿主或 UI 测试会启动应用，需要单独授权。实际窗口聚焦、Dock 切换、快捷键和蓝牙交互在启动应用后验收。

## 隔离边界

- SwiftPM 的 `random_thoughts` 库直接编译清单列出的生产 Swift 文件。生产入口、应用 Delegate、窗口操作、蓝牙和系统操作适配器由 Xcode 应用目标编译。
- 模型监控使用注入的 URLSession、UserDefaults、时钟和调度器。隔离测试通过合成传输提供响应，通过调度屏障推进固定时钟。
- 每次运行创建临时根目录，各测试使用独立目录和随机 UserDefaults suite。测试结束清理各自的目录和 suite，脚本退出清理整次运行目录。
- 沙盒只允许测试加载器执行，阻止网络和蓝牙服务访问。用户主目录中的读取限于仓库，测试写入限于临时根目录。
- 菜单测试检查原生菜单动作和快捷键，布局测试通过 `NSHostingView.fittingSize` 测量内容。两类测试均在无生产应用宿主的环境中执行。
