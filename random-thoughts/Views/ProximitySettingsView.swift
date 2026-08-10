import AppKit
import Combine
import SwiftUI

struct ProximitySettingsView: View {
    let store: ProximityLockStore
    @State private var aliasEditorPresented = false
    @State private var aliasDraft = ""
    @State private var devicePickerPresented = false
    @State private var pendingDevicePickerAction: ProximityDevicePickerAction?

    var body: some View {
        Form {
            deviceSection
            thresholdSection
            behaviorSection
            securitySection
            automationSection
        }
        .formStyle(.grouped)
        .navigationTitle("蓝牙解锁")
        .onAppear {
            store.refreshSystemState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            store.refreshSystemState()
        }
        .alert("蓝牙解锁操作失败", isPresented: errorPresented) {
            Button("好") { store.clearError() }
        } message: {
            Text(store.lastError ?? "未知错误")
        }
        .alert("重命名设备", isPresented: $aliasEditorPresented) {
            TextField("设备名称", text: $aliasDraft)
            Button("取消", role: .cancel) {}
            Button("保存") {
                store.renameSelectedDevice(to: aliasDraft)
            }
        } message: {
            Text("名称仅保存在这台 Mac 上；留空可恢复设备报告的名称。")
        }
        .sheet(
            isPresented: $devicePickerPresented,
            onDismiss: performPendingDevicePickerAction
        ) {
            ProximityDevicePickerSheet(store: store) { action in
                pendingDevicePickerAction = action
            }
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent("当前设备") {
                HStack(spacing: 8) {
                    Text(store.selectedDeviceName ?? "未选择设备")
                        .foregroundStyle(
                            store.configuration.selectedDeviceID == nil
                                ? .secondary
                                : .primary
                        )
                        .lineLimit(1)

                    Button(store.configuration.selectedDeviceID == nil ? "选择…" : "更换…") {
                        devicePickerPresented = true
                    }
                    .pointerStyle(.link)

                    if store.configuration.selectedDeviceID != nil {
                        Button("停止监控", role: .destructive) {
                            store.stopMonitoring()
                        }
                        .pointerStyle(.link)
                    }
                }
            }

            if store.configuration.selectedDeviceID != nil {
                LabeledContent("显示名称") {
                    HStack(spacing: 8) {
                        Text(store.selectedDeviceName ?? "未知蓝牙设备")
                            .foregroundStyle(.secondary)
                        Button("重命名…") {
                            aliasDraft = store.selectedDeviceName ?? ""
                            aliasEditorPresented = true
                        }
                        .pointerStyle(.link)
                    }
                }
            }

            LabeledContent("当前状态") {
                Label(store.statusText, systemImage: store.statusSystemImage)
                    .foregroundStyle(statusColor)
            }

            Button {
                store.lockNow()
            } label: {
                Label("立即锁定屏幕", systemImage: "lock.display")
            }
            .buttonStyle(.borderedProminent)
            .pointerStyle(.link)
        } header: {
            Text("监控设备")
        } footer: {
            Text("点击“选择…”或“更换…”时会扫描附近的低功耗蓝牙设备。设备未报告名称时，可选择后为它设置一个仅在本机使用的名称。")
        }
    }

    private var thresholdSection: some View {
        Section {
            Picker("解锁 RSSI", selection: optionalRSSIBinding(\.unlockRSSI)) {
                Text("禁用").tag(Int?.none)
                ForEach(store.availableUnlockRSSIValues, id: \.self) { value in
                    Text("\(value) dBm").tag(Optional(value))
                }
            }
            .pointerStyle(.link)

            Picker("锁定 RSSI", selection: optionalRSSIBinding(\.lockRSSI)) {
                ForEach(store.availableLockRSSIValues, id: \.self) { value in
                    Text("\(value) dBm").tag(Optional(value))
                }
                Text("禁用").tag(Int?.none)
            }
            .pointerStyle(.link)

            Picker("延迟锁定", selection: valueBinding(\.lockDelay)) {
                ForEach(ProximityLockStore.lockDelayValues, id: \.self) { value in
                    Text(durationLabel(value)).tag(value)
                }
            }
            .pointerStyle(.link)

            Picker("无信号超时", selection: valueBinding(\.signalTimeout)) {
                ForEach(ProximityLockStore.signalTimeoutValues, id: \.self) { value in
                    Text(durationLabel(value)).tag(value)
                }
            }
            .pointerStyle(.link)

            Stepper(
                value: valueBinding(\.minimumScanRSSI),
                in: ProximityLockStore.minimumScanRSSIRange
            ) {
                LabeledContent("扫描最低 RSSI") {
                    Text("\(store.configuration.minimumScanRSSI) dBm")
                        .monospacedDigit()
                }
            }
            .pointerStyle(.link)
        } header: {
            Text("距离与超时")
        } footer: {
            Text("解锁阈值必须大于或等于锁定阈值。RSSI 越接近 0，设备需要离 Mac 越近。")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("靠近时唤醒显示器", isOn: valueBinding(\.wakeOnProximity))
                .pointerStyle(.link)
            Toggle("唤醒但不自动输入密码", isOn: valueBinding(\.wakeWithoutUnlocking))
                .pointerStyle(.link)
            Toggle("锁定期间暂停“正在播放”", isOn: valueBinding(\.pauseNowPlaying))
                .pointerStyle(.link)
            Toggle("使用屏幕保护程序锁定", isOn: valueBinding(\.useScreensaverToLock))
                .pointerStyle(.link)
            Toggle("锁定后立即关闭显示器", isOn: valueBinding(\.turnOffDisplayOnLock))
                .disabled(store.configuration.useScreensaverToLock)
                .pointerStyle(store.configuration.useScreensaverToLock ? .default : .link)
            Toggle("被动模式", isOn: valueBinding(\.passiveMode))
                .pointerStyle(.link)
        } header: {
            Text("锁定与唤醒行为")
        } footer: {
            Text("被动模式不会主动连接设备，适合蓝牙热点、键鼠或 2.4 GHz Wi‑Fi 受到干扰时使用。")
        }
    }

    private var securitySection: some View {
        Section {
            LabeledContent("登录密码") {
                Label(
                    store.hasPassword ? "已存储在钥匙串" : "尚未设置",
                    systemImage: store.hasPassword ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(store.hasPassword ? Color.green : Color.orange)
            }

            HStack {
                Button(store.hasPassword ? "更改密码…" : "设置密码…") {
                    store.promptForPassword()
                }
                .pointerStyle(.link)

                if store.hasPassword {
                    Button("移除密码", role: .destructive) {
                        store.deletePassword()
                    }
                    .pointerStyle(.link)
                }
            }

            LabeledContent("辅助功能") {
                Label(
                    store.accessibilityTrusted ? "已授权" : "需要授权",
                    systemImage: store.accessibilityTrusted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(store.accessibilityTrusted ? Color.green : Color.orange)
            }

            if !store.accessibilityTrusted {
                Button("请求辅助功能权限") {
                    store.requestAccessibilityPermission()
                }
                .pointerStyle(.link)
            }
        } header: {
            Text("自动解锁与权限")
        } footer: {
            Text("自动解锁会从钥匙串读取当前用户密码，并通过辅助功能向锁屏界面输入。")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle("登录时启动随想", isOn: launchAtLoginBinding)
                .pointerStyle(.link)

            LabeledContent("事件脚本") {
                Text(store.scriptPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Button("在 Finder 中打开脚本目录") {
                store.openApplicationScriptsFolder()
            }
            .pointerStyle(.link)
        } header: {
            Text("自动化")
        } footer: {
            Text("可执行文件名固定为 event；参数为 away、lost、unlocked 或 intruded，并附带最近一次 RSSI。")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginRequested },
            set: { store.setLaunchAtLogin($0) }
        )
    }

    private func performPendingDevicePickerAction() {
        defer { pendingDevicePickerAction = nil }
        switch pendingDevicePickerAction {
        case .select(let selection):
            store.selectDevice(selection)
        case .stopMonitoring:
            store.stopMonitoring()
        case nil:
            break
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { isPresented in
                if !isPresented { store.clearError() }
            }
        )
    }

    private var statusColor: Color {
        if store.latestRSSI != nil { return .green }
        if store.bluetoothState == .poweredOff || store.bluetoothState == .unauthorized {
            return .orange
        }
        return .secondary
    }

    private func valueBinding<Value>(
        _ keyPath: WritableKeyPath<ProximityConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.configuration[keyPath: keyPath] },
            set: { value in
                store.setConfigurationValue(keyPath, to: value)
            }
        )
    }

    private func optionalRSSIBinding(
        _ keyPath: WritableKeyPath<ProximityConfiguration, Int?>
    ) -> Binding<Int?> {
        valueBinding(keyPath)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration)) 秒"
        }
        return "\(Int(duration / 60)) 分钟"
    }
}
