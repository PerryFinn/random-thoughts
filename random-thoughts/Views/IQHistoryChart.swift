import Charts
import SwiftUI

struct IQHistoryChart: View {
    let samples: [IntelligenceIQHistorySample]

    @State private var hoveredSample: IntelligenceIQHistorySample?

    private let lineGradient = LinearGradient(
        colors: [.cyan, .indigo],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if samples.isEmpty {
                ContentUnavailableView(
                    "暂无历史 IQ 数据",
                    systemImage: "chart.xyaxis.line"
                )
                .frame(maxWidth: .infinity, minHeight: 135)
            } else {
                chart

                if samples.count == 1 {
                    Text("历史快照积累后，这里将显示 IQ 的变化曲线。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var header: some View {
        Label("IQ 历史趋势", systemImage: "chart.xyaxis.line")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("时间", sample.at),
                    y: .value("IQ", sample.iq)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan.opacity(0.2), .indigo.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", sample.at),
                    y: .value("IQ", sample.iq)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineGradient)
            }

            if let hoveredSample {
                RuleMark(x: .value("悬停时间", hoveredSample.at))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.45))

                PointMark(
                    x: .value("悬停时间", hoveredSample.at),
                    y: .value("悬停 IQ", hoveredSample.iq)
                )
                .symbolSize(42)
                .foregroundStyle(.indigo)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                    .foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel(format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
                    .foregroundStyle(.secondary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.primary.opacity(0.025))
                .clipShape(.rect(cornerRadius: 6))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                updateHoveredSample(
                                    at: location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            case .ended:
                                hoveredSample = nil
                            }
                        }

                    if let hoveredSample,
                       let position = tooltipPosition(
                           for: hoveredSample,
                           proxy: proxy,
                           geometry: geometry
                       ) {
                        tooltip(for: hoveredSample)
                            .position(position)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 145)
        .accessibilityLabel("IQ 历史趋势图")
    }

    private func updateHoveredSample(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            hoveredSample = nil
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location),
              let hoveredDate: Date = proxy.value(atX: location.x - plotFrame.minX) else {
            hoveredSample = nil
            return
        }

        hoveredSample = samples.min {
            abs($0.at.timeIntervalSince(hoveredDate))
                < abs($1.at.timeIntervalSince(hoveredDate))
        }
    }

    private func tooltipPosition(
        for sample: IntelligenceIQHistorySample,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> CGPoint? {
        guard let plotFrameAnchor = proxy.plotFrame,
              let relativeX = proxy.position(forX: sample.at),
              let relativeY = proxy.position(forY: sample.iq) else {
            return nil
        }

        let plotFrame = geometry[plotFrameAnchor]
        let pointX = plotFrame.minX + relativeX
        let pointY = plotFrame.minY + relativeY
        let tooltipSize = CGSize(width: 140, height: 46)
        let horizontalInset = tooltipSize.width / 2
        let clampedX = min(
            max(pointX, plotFrame.minX + horizontalInset),
            plotFrame.maxX - horizontalInset
        )
        let verticalOffset = tooltipSize.height / 2 + 10
        let preferredY = pointY - verticalOffset
        let fallbackY = pointY + verticalOffset
        let unclampedY = preferredY < plotFrame.minY ? fallbackY : preferredY
        let clampedY = min(
            max(unclampedY, plotFrame.minY + tooltipSize.height / 2),
            plotFrame.maxY - tooltipSize.height / 2
        )

        return CGPoint(x: clampedX, y: clampedY)
    }

    private func tooltip(for sample: IntelligenceIQHistorySample) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("IQ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(sample.iq, format: .number.precision(.fractionLength(1)))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 140, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
    }

    private var xDomain: ClosedRange<Date> {
        guard let firstDate = samples.first?.at,
              let lastDate = samples.last?.at else {
            let now = Date()
            return now.addingTimeInterval(-1)...now.addingTimeInterval(1)
        }

        guard firstDate != lastDate else {
            let lowerBound = firstDate.addingTimeInterval(-12 * 60 * 60)
            let upperBound = lastDate.addingTimeInterval(12 * 60 * 60)
            return lowerBound...upperBound
        }

        return firstDate...lastDate
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimumIQ = samples.map(\.iq).min(),
              let maximumIQ = samples.map(\.iq).max() else {
            return 0...1
        }

        let padding = max((maximumIQ - minimumIQ) * 0.18, 1)
        return (minimumIQ - padding)...(maximumIQ + padding)
    }
}
