import SwiftUI

struct SettingsView: View {
    let store: IntelligenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("状态栏显示")
                .font(.title2.bold())

            HStack {
                Button("选择前 \(IntelligenceStore.selectionLimit) 项") {
                    store.selectAll()
                }
                .pointerStyle(.link)

                Button("全部清除") {
                    store.clearSelection()
                }
                .pointerStyle(.link)

                Spacer()

                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新模型列表", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing)
                .pointerStyle(store.isRefreshing ? .default : .link)
            }

            if store.points.isEmpty {
                ContentUnavailableView {
                    Label("暂无模型", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "正在从 Codex Radar 获取数据…")
                } actions: {
                    Button("重试") {
                        Task { await store.refresh() }
                    }
                    .pointerStyle(.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("监控指标")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("\(store.selectedPointIDs.count)/\(IntelligenceStore.selectionLimit)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(.regularMaterial)

                    Divider()

                    List {
                        ForEach(store.modelNames, id: \.self) { model in
                            Section {
                                ForEach(store.points(for: model)) { point in
                                    Toggle(isOn: selectionBinding(for: point)) {
                                        HStack {
                                            Text(point.effort)
                                                .fontWeight(.medium)
                                                .frame(width: 72, alignment: .leading)

                                            Text("IQ \(point.iq.formatted(.number.precision(.fractionLength(1))))")
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            if let minutes = point.averageMinutes {
                                                Text("约 \(minutes.formatted(.number.precision(.fractionLength(0)))) 分钟")
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(!store.canSelect(point))
                                    .pointerStyle(store.canSelect(point) ? .link : .default)
                                    .help(
                                        store.canSelect(point)
                                            ? ""
                                            : "最多只能追踪 \(IntelligenceStore.selectionLimit) 项"
                                    )
                                }
                            } header: {
                                HStack {
                                    Text(model)

                                    Spacer()

                                    Text("平均耗时")
                                        .frame(width: 88, alignment: .trailing)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }

            HStack {
                Text("最多追踪 \(IntelligenceStore.selectionLimit) 项 · 自动刷新间隔：30 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let updatedAt = store.sourceUpdatedAt {
                    Text("数据源更新：\(Self.formatSourceUpdatedAt(updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .onAppear {
            SettingsWindowPresenter.bringToFront()
        }
    }

    static func formatSourceUpdatedAt(
        _ date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-dd-MM HH:mm"
        return formatter.string(from: date)
    }

    private func selectionBinding(for point: IntelligencePoint) -> Binding<Bool> {
        Binding(
            get: { store.isSelected(point) },
            set: { store.setSelected($0, point: point) }
        )
    }
}
