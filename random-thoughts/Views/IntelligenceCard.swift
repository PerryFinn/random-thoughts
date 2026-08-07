import SwiftUI

struct IntelligenceCard: View {
    let point: IntelligencePoint

    private let scoreGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.76, blue: 1.0),
            Color(red: 0.50, green: 0.45, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(point.effort.lowercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let runs24h = point.runs24h {
                    Label("\(runs24h)", systemImage: "chart.bar.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .help("最近 24 小时运行次数")
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(point.iq, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(scoreGradient)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    MetricLabel(systemImage: "dollarsign.circle", text: priceText)
                    MetricLabel(systemImage: "clock", text: durationText)
                }
                .padding(.bottom, 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 106)
        .background(alignment: .bottomLeading) {
            Circle()
                .fill(scoreGradient)
                .frame(width: 92, height: 92)
                .blur(radius: 30)
                .opacity(0.10)
                .offset(x: -18, y: 30)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(point.cardTitle)，Score \(point.iq.formatted(.number.precision(.fractionLength(1))))")
    }

    private var priceText: String {
        guard let price = point.averagePriceUSD else { return "—" }
        return String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), price)
    }

    private var durationText: String {
        guard let minutes = point.averageMinutes else { return "—" }
        return "\(minutes.formatted(.number.precision(.fractionLength(0))))分钟"
    }
}

private struct MetricLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}
