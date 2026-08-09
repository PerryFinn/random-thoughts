import AppKit
import Combine
import SwiftUI

struct ProximitySettingsView: View {
    let store: ProximityLockStore

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
            store.startScanning()
        }
        .onDisappear {
            store.stopScanning()
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
    }

    private var deviceSection: some View {
        Section {
            Picker("设备", selection: selectedDeviceBinding) {
                Text("未选择设备").tag(UUID?.none)

                if let selectedID = store.configuration.selectedDeviceID,
                   !store.devices.contains(where: { $0.id == selectedID }) {
                    Text(store.selectedDeviceName ?? selectedID.uuidString)
                        .tag(Optional(selectedID))
                }

                ForEach(store.devices) { device in
                    HStack {
                        Text(device.displayTitle)
                        Spacer()
                        Text("\(device.rssi) dBm")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(Optional(device.id))
                }
            }
            .pointerStyle(.link)

            LabeledContent("当前状态") {
                Label(store.statusText, systemImage: store.statusSystemImage)
                    .foregroundStyle(statusColor)
            }

            HStack {
                Button {
                    store.startScanning()
                } label: {
                    Label(
                        store.isScanning ? "正在扫描" : "重新扫描",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
                .disabled(store.isScanning)
                .pointerStyle(store.isScanning ? .default : .link)

                Button {
                    store.lockNow()
                } label: {
                    Label("立即锁定屏幕", systemImage: "lock.display")
                }
                .buttonStyle(.borderedProminent)
                .pointerStyle(.link)
            }
        } header: {
            Text("监控设备")
        } footer: {
            Text("打开此页面时会持续扫描附近的低功耗蓝牙设备。关闭设置后，随想仍会监控已选择的设备。")
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

    private var selectedDeviceBinding: Binding<UUID?> {
        Binding(
            get: { store.configuration.selectedDeviceID },
            set: { store.selectDevice($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginRequested },
            set: { store.setLaunchAtLogin($0) }
        )
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
