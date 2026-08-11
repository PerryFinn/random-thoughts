import AppKit
import OSLog
import SwiftUI

struct MenuBarPanel: View {
    static let panelWidth: CGFloat = 568

    let store: IntelligenceStore
    let proximityStore: ProximityLockStore?
    @Environment(\.openSettings) private var openSettings
    @State private var selectedPointID: IntelligencePoint.ID?
    @State private var roulettePointID: IntelligencePoint.ID?
    @State private var rouletteRollCount = 0

    init(
        store: IntelligenceStore,
        selectedPointID: IntelligencePoint.ID? = nil,
        proximityStore: ProximityLockStore? = nil
    ) {
        self.store = store
        self.proximityStore = proximityStore
        _selectedPointID = State(initialValue: selectedPointID)
    }

    var body: some View {
        Group {
            if let selectedPoint {
                IntelligenceDetailView(
                    point: selectedPoint,
                    iqChange24Hours: store.iqChange24Hours(for: selectedPoint),
                    iqHistory: store.iqHistory(for: selectedPoint),
                    confidenceWarning: store.confidenceWarning(for: selectedPoint),
                    sourceUpdatedAt: store.sourceUpdatedAt,
                    onBack: showOverview
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                overview
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: Self.panelWidth)
        .animation(.snappy(duration: 0.22), value: selectedPointID)
        .onChange(of: store.points.map(\.id)) { _, availablePointIDs in
            guard let selectedPointID,
                  !availablePointIDs.contains(selectedPointID) else {
                return
            }
            self.selectedPointID = nil
        }
        .onChange(of: store.selectedPoints.map(\.id)) { _, selectedPointIDs in
            guard let roulettePointID,
                  !selectedPointIDs.contains(roulettePointID) else {
                return
            }
            self.roulettePointID = nil
        }
        .task {
            AppTelemetry.menuBar.debug("Menu bar panel presented")
        }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            header

            if let roulettePoint {
                ModelRouletteCard(point: roulettePoint) {
                    showDetail(for: roulettePoint)
                }
                .id(rouletteRollCount)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if store.points.isEmpty {
                loadingState
            } else if store.selectedPoints.isEmpty {
                emptySelectionState
            } else {
                ScrollView(.vertical) {
                    GlassEffectContainer(spacing: Layout.cardSpacing) {
                        VStack(alignment: .leading, spacing: Layout.groupSpacing) {
                            ForEach(selectedModelNames, id: \.self) { model in
                                VStack(alignment: .leading, spacing: Layout.headerSpacing) {
                                    modelGroupHeader(for: model)

                                    LazyVGrid(columns: gridColumns, spacing: Layout.cardSpacing) {
                                        ForEach(selectedPoints(for: model)) { point in
                                            Button {
                                                showDetail(for: point)
                                            } label: {
                                                IntelligenceCard(
                                                    point: point,
                                                    iqChange24Hours: store.iqChange24Hours(for: point),
                                                    comparison: store.comparisonWithNextLowerEffort(for: point),
                                                    confidenceWarning: store.confidenceWarning(for: point)
                                                )
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .pointerStyle(.link)
                                            .accessibilityHint("打开模型详情")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .padding(.vertical, 1)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(cardContentHeight, Layout.maximumCardAreaHeight))
            }

            footer
        }
        .padding(14)
    }

    private var selectedPoint: IntelligencePoint? {
        guard let selectedPointID else { return nil }
        return store.points.first { $0.id == selectedPointID }
    }

    private var roulettePoint: IntelligencePoint? {
        guard let roulettePointID else { return nil }
        return store.selectedPoints.first { $0.id == roulettePointID }
    }

    private func showDetail(for point: IntelligencePoint) {
        AppTelemetry.menuBar.info(
            "Model detail opened; pointID=\(point.id, privacy: .private(mask: .hash))"
        )
        selectedPointID = point.id
    }

    private func showOverview() {
        AppTelemetry.menuBar.info("Model detail closed")
        selectedPointID = nil
    }

    private func rollRoulette() {
        guard let point = ModelRoulette.pick(
            from: store.selectedPoints,
            excluding: roulettePointID
        ) else {
            return
        }

        AppTelemetry.menuBar.info(
            "Model roulette rolled; pointID=\(point.id, privacy: .private(mask: .hash))"
        )
        withAnimation(.bouncy(duration: 0.45)) {
            roulettePointID = point.id
            rouletteRollCount += 1
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                Text("随想")
                    .font(.headline)

                Text("智能、成本与速度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !store.selectedPoints.isEmpty {
                Button(action: rollRoulette) {
                    HStack(spacing: 5) {
                        Image(systemName: "die.face.5.fill")
                            .symbolEffect(.bounce, value: rouletteRollCount)
                        Text(roulettePoint == nil ? "替我选" : "再摇一次")
                    }
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)
                .help("从当前展示的模型中随机挑一个")
            }
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
                Button("打开设置") {
                    openSettings()
                    SettingsWindowPresenter.bringToFront()
                }
                .pointerStyle(.link)
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
            if let proximityStore {
                HStack(spacing: 8) {
                    Image(systemName: proximityStore.statusSystemImage)
                        .foregroundStyle(
                            proximityStore.latestRSSI == nil
                                ? Color.secondary
                                : Color.green
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(proximityStore.selectedDeviceName ?? "蓝牙解锁")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(proximityStore.statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        proximityStore.lockNow()
                    } label: {
                        Label("锁屏", systemImage: "lock.display")
                    }
                    .buttonStyle(.borderless)
                    .pointerStyle(.link)
                }
            }

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
                    AppTelemetry.menuBar.info("Settings command selected")
                    openSettings()
                    SettingsWindowPresenter.bringToFront()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)

                Button {
                    AppTelemetry.menuBar.info("Quit command selected")
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)
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
            GridItem(.flexible(), spacing: Layout.cardSpacing),
            GridItem(.flexible(), spacing: Layout.cardSpacing)
        ]
    }

    private var cardContentHeight: CGFloat {
        let groupHeights = selectedModelNames.map { model in
            let pointCount = selectedPoints(for: model).count
            let rowCount = CGFloat((pointCount + Layout.columnCount - 1) / Layout.columnCount)
            let gridHeight = rowCount * IntelligenceCard.minimumHeight
                + max(0, rowCount - 1) * Layout.cardSpacing
            return Layout.groupHeaderHeight + Layout.headerSpacing + gridHeight
        }

        return groupHeights.reduce(0, +)
            + CGFloat(max(0, groupHeights.count - 1)) * Layout.groupSpacing
            + 2
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

            Spacer()
        }
        .padding(.horizontal, 3)
        .frame(height: Layout.groupHeaderHeight)
    }

    private enum Layout {
        static let columnCount = 2
        static let cardSpacing: CGFloat = 10
        static let groupSpacing: CGFloat = 16
        static let headerSpacing: CGFloat = 8
        static let groupHeaderHeight: CGFloat = 18
        static let maximumCardAreaHeight: CGFloat = 590
    }
}
