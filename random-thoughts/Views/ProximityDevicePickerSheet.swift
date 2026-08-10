import SwiftUI

enum ProximityDevicePickerAction {
    case select(ProximityDeviceSelection)
    case stopMonitoring
}

struct ProximityDevicePickerSheet: View {
    static let windowSize = CGSize(width: 500, height: 420)

    let store: ProximityLockStore
    let onCommit: (ProximityDevicePickerAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            controls
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear {
            store.beginDeviceSelection()
        }
        .onDisappear {
            store.endDeviceSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("选择监控设备")
                .font(.title2.bold())
            Text("扫描期间设备顺序保持不变，新发现的设备会添加到列表末尾。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var deviceList: some View {
        if store.devicePickerEntries.isEmpty {
            ContentUnavailableView {
                Label("尚未发现设备", systemImage: "antenna.radiowaves.left.and.right")
            } description: {
                Text("请确认设备在附近且蓝牙可被发现。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List(store.devicePickerEntries) { entry in
                    deviceButton(entry, at: context.date)
                }
                .listStyle(.inset)
            }
        }
    }

    private func deviceButton(
        _ entry: ProximityDevicePickerEntry,
        at date: Date
    ) -> some View {
        let signal = entry.signal(
            at: date,
            bluetoothPoweredOn: store.bluetoothState == .poweredOn
        )
        return Button {
            onCommit(.select(entry.selection))
            dismiss()
        } label: {
            deviceRow(entry, signal: signal)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(
            signal.isAvailable
                ? "最近信号：\(entry.rssi.map(String.init) ?? "--") dBm"
                : "当前没有收到设备信号"
        )
    }

    private func deviceRow(
        _ entry: ProximityDevicePickerEntry,
        signal: ProximityDeviceSignal
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: entry.id == store.configuration.selectedDeviceID
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .foregroundStyle(
                entry.id == store.configuration.selectedDeviceID
                    ? Color.accentColor
                    : Color.secondary
            )
            .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(signal.isAvailable ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(signal.description)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.id == store.configuration.selectedDeviceID {
                Text("当前设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if store.configuration.selectedDeviceID != nil {
                Button("停止监控", role: .destructive) {
                    onCommit(.stopMonitoring)
                    dismiss()
                }
                .pointerStyle(.link)
            }

            Spacer()

            discoveryStatus

            Button("重新扫描") {
                store.restartDeviceDiscovery()
            }
            .disabled(store.bluetoothState != .poweredOn)
            .pointerStyle(store.bluetoothState == .poweredOn ? .link : .default)

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .pointerStyle(.link)
        }
        .padding(16)
    }

    @ViewBuilder
    private var discoveryStatus: some View {
        switch store.bluetoothState {
        case .poweredOn:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在扫描…")
            }
        case .poweredOff:
            Label("蓝牙已关闭", systemImage: "bluetooth.slash")
        case .unauthorized:
            Label("没有蓝牙权限", systemImage: "exclamationmark.triangle")
        case .unsupported:
            Text("不支持蓝牙低功耗")
        case .resetting, .unknown:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在准备蓝牙…")
            }
        }
    }

}
