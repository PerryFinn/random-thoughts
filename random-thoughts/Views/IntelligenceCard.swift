import SwiftUI

struct IntelligenceCard: View {
    static let minimumHeight: CGFloat = 88

    let point: IntelligencePoint
    let iqChange24Hours: Double?
    let comparison: IntelligencePointComparison?
    let confidenceWarning: IntelligenceConfidenceWarning?

    private let iqGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.76, blue: 1.0),
            Color(red: 0.50, green: 0.45, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(point.effort.lowercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let confidenceWarning {
                    Label(confidenceWarning.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(confidenceWarning.detail)
                }
            }

            HStack(alignment: .bottom, spacing: 5) {
                Text(point.iq, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(iqGradient)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .help(iqComparisonHelp)

                VStack(alignment: .leading, spacing: -1) {
                    Text("IQ")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    if let iqChange24Hours {
                        Text(trendText(for: iqChange24Hours))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(trendColor(for: iqChange24Hours))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .help(trendHelp(for: iqChange24Hours))
                    }
                }
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            HStack(spacing: 10) {
                CompactMetric(
                    value: priceText,
                    systemImage: "dollarsign",
                    help: "平均成本"
                )

                Divider()
                    .frame(height: 12)

                CompactMetric(
                    value: durationText,
                    systemImage: "clock",
                    help: "平均耗时"
                )

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.minimumHeight)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var priceText: String {
        guard let price = point.averagePriceUSD else { return "—" }
        return String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), price)
    }

    private var durationText: String {
        guard let minutes = point.averageMinutes else { return "—" }
        return "\(minutes.formatted(.number.precision(.fractionLength(1)))) 分"
    }

    private var accessibilitySummary: String {
        let iq = point.iq.formatted(.number.precision(.fractionLength(1)))
        var parts = [
            point.groupTitle,
            "\(point.effort) 推理强度",
            "IQ \(iq)",
            "平均成本 \(priceText)",
            "平均耗时 \(durationText)"
        ]

        if let iqChange24Hours {
            parts.append(trendHelp(for: iqChange24Hours))
        }

        if let confidenceWarning {
            parts.append(confidenceWarning.detail)
        }

        return parts.joined(separator: "，")
    }

    private var iqComparisonHelp: String {
        guard let comparison else {
            return "当前已是同模型最低推理档位"
        }

        var metrics = ["IQ \(signedNumber(comparison.iqDelta, fractionLength: 1))"]

        if let priceDeltaUSD = comparison.priceDeltaUSD {
            metrics.append("成本 \(signedCurrency(priceDeltaUSD))")
        }

        if let minutesDelta = comparison.minutesDelta {
            metrics.append("耗时 \(signedNumber(minutesDelta, fractionLength: 1)) 分")
        }

        return "相比下一低档 \(comparison.baselineEffort)：\(metrics.joined(separator: " · "))"
    }

    private func trendText(for change: Double) -> String {
        let value = abs(change).formatted(.number.precision(.fractionLength(1)))

        if change > 0.05 {
            return "↑ \(value)"
        } else if change < -0.05 {
            return "↓ \(value)"
        } else {
            return "— 0.0"
        }
    }

    private func trendHelp(for change: Double) -> String {
        let value = abs(change).formatted(.number.precision(.fractionLength(1)))

        if change > 0.05 {
            return "相比 24 小时前上升 \(value) IQ"
        } else if change < -0.05 {
            return "相比 24 小时前下降 \(value) IQ"
        } else {
            return "相比 24 小时前基本不变"
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

    private func signedNumber(_ value: Double, fractionLength: Int) -> String {
        let magnitude = abs(value).formatted(
            .number.precision(.fractionLength(fractionLength))
        )
        return value >= 0 ? "+\(magnitude)" : "−\(magnitude)"
    }

    private func signedCurrency(_ value: Double) -> String {
        let magnitude = String(
            format: "$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            abs(value)
        )
        return value >= 0 ? "+\(magnitude)" : "−\(magnitude)"
    }
}

private struct CompactMetric: View {
    let value: String
    let systemImage: String
    let help: String

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .help(help)
    }
}
