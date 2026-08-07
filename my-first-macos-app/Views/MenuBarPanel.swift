import AppKit
import SwiftUI

struct MenuBarPanel: View {
    let store: IntelligenceStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            header

            if store.points.isEmpty {
                loadingState
            } else if store.selectedPoints.isEmpty {
                emptySelectionState
            } else {
                GlassEffectContainer(spacing: 10) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(selectedModelNames, id: \.self) { model in
                            VStack(alignment: .leading, spacing: 7) {
                                modelGroupHeader(for: model)

                                LazyVGrid(columns: gridColumns, spacing: 10) {
                                    ForEach(selectedPoints(for: model)) { point in
                                        IntelligenceCard(point: point)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 568)
        .task {
            store.startUpdating()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("IQ Radar")
                .font(.headline)

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("立即刷新")
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 10) {
            if store.isRefreshing {
                ProgressView()
                Text("正在获取模型数据…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(store.errorMessage ?? "暂时没有模型数据")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await store.refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var emptySelectionState: some View {
        ContentUnavailableView(
            "尚未选择模型",
            systemImage: "checklist.unchecked",
            description: Text("请在设置中选择要显示的模型与推理强度。")
        )
        .frame(height: 160)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(store.errorMessage == nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    openSettings()
                    SettingsWindowPresenter.bringToFront()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var statusText: String {
        if store.errorMessage != nil, !store.points.isEmpty {
            return "更新失败，正在显示缓存"
        }

        if let updatedAt = store.sourceUpdatedAt {
            return "数据更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))"
        }

        return store.isRefreshing ? "正在更新…" : "等待更新"
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var selectedModelNames: [String] {
        store.modelNames.filter { !selectedPoints(for: $0).isEmpty }
    }

    private func selectedPoints(for model: String) -> [IntelligencePoint] {
        store.selectedPoints.filter { $0.model == model }
    }

    private func modelGroupHeader(for model: String) -> some View {
        let points = selectedPoints(for: model)
        let displayName = points.first?.groupTitle ?? model

        return HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text(displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("\(points.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.055), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 3)
        .frame(height: 16)
    }

}
