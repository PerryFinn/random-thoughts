import SwiftUI

struct IntelligenceDetailView: View {
    static let panelHeight: CGFloat = 560

    let point: IntelligencePoint
    let iqChange24Hours: Double?
    let iqHistory: [IntelligenceIQHistorySample]
    let confidenceWarning: IntelligenceConfidenceWarning?
    let sourceUpdatedAt: Date?
    let recommendation: ModelRecommendation?
    let onBack: () -> Void

    private let iqGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.76, blue: 1.0),
            Color(red: 0.50, green: 0.45, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 14) {
            header

            ScrollView(.vertical) {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if let recommendation,
                           recommendation.point.id == point.id {
                            recommendationCard(recommendation)
                        }

                        hero
                        primaryMetrics
                        IQHistoryChart(samples: iqHistory)

                        if let confidenceWarning {
                            dataQualityWarning(confidenceWarning)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .padding(14)
        .frame(width: MenuBarPanel.panelWidth, height: Self.panelHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .keyboardShortcut(.cancelAction)

            Divider()
                .frame(height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(point.groupTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(point.effort.lowercased()) 推理强度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("综合智能")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(point.iq, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundStyle(iqGradient)
                        .contentTransition(.numericText())

                    Text("IQ")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let iqChange24Hours {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("24 小时")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Label(
                        trendText(for: iqChange24Hours),
                        systemImage: trendSystemImage(for: iqChange24Hours)
                    )
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(trendColor(for: iqChange24Hours))
                    .monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func recommendationCard(_ recommendation: ModelRecommendation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recommendation.strategy.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.indigo)
                .symbolEffect(.bounce, value: recommendation.strategy)

            VStack(alignment: .leading, spacing: 3) {
                Text("帮你选了「\(recommendation.strategy.title)」")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))

                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.indigo.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryMetrics: some View {
        HStack(spacing: 10) {
            DetailMetricTile(
                title: "平均成本",
                value: priceText,
                systemImage: "dollarsign.circle.fill"
            )

            DetailMetricTile(
                title: "平均耗时",
                value: durationText,
                systemImage: "clock.fill"
            )
        }
    }

    private func dataQualityWarning(_ warning: IntelligenceConfidenceWarning) -> some View {
        Label(warning.detail, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label(latestUpdateText, systemImage: "clock.arrow.circlepath")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var priceText: String {
        guard let price = point.averagePriceUSD else { return "—" }
        return String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), price)
    }

    private var durationText: String {
        guard let minutes = point.averageMinutes else { return "—" }
        return "\(minutes.formatted(.number.precision(.fractionLength(1)))) 分"
    }

    private var latestUpdateText: String {
        Self.formatLatestUpdate(
            latestGradedAt: point.latestGradedAt,
            sourceUpdatedAt: sourceUpdatedAt
        )
    }

    static func formatLatestUpdate(
        latestGradedAt: String?,
        sourceUpdatedAt: Date?,
        relativeTo referenceDate: Date = .now
    ) -> String {
        let latestGradedDate = latestGradedAt.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        guard let updatedAt = latestGradedDate ?? sourceUpdatedAt else {
            return "等待数据更新时间"
        }

        let elapsed = max(0, referenceDate.timeIntervalSince(updatedAt))
        if elapsed < 60 {
            return "刚刚更新"
        } else if elapsed < 60 * 60 {
            return "最近更新于 \(Int(elapsed / 60)) 分钟前"
        } else if elapsed < 24 * 60 * 60 {
            return "最近更新于 \(Int(elapsed / (60 * 60))) 小时前"
        } else {
            return "最近更新于 \(Int(elapsed / (24 * 60 * 60))) 天前"
        }
    }

    private func trendText(for change: Double) -> String {
        abs(change).formatted(.number.precision(.fractionLength(1)))
    }

    private func trendSystemImage(for change: Double) -> String {
        if change > 0.05 {
            return "arrow.up.right"
        } else if change < -0.05 {
            return "arrow.down.right"
        } else {
            return "minus"
        }
    }

    private func trendColor(for change: Double) -> Color {
        if change > 0.05 {
            return .green
        } else if change < -0.05 {
            return .orange
        } else {
            return .secondary
        }
    }

}

private struct DetailMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
