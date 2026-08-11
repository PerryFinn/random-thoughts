import SwiftUI

struct ModelRouletteCard: View {
    let point: IntelligencePoint
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("今晚就用它")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)

                    Text("\(point.groupTitle) · \(point.effort.lowercased())")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(1)

                    Text(encouragement)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(point.iq, format: .number.precision(.fractionLength(1)))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("IQ")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .glassEffect(
            .regular.tint(.indigo.opacity(0.12)).interactive(),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityLabel(
            "今晚推荐 \(point.groupTitle)，\(point.effort.lowercased()) 推理强度，IQ \(point.iq.formatted(.number.precision(.fractionLength(1))))"
        )
        .accessibilityHint("打开模型详情")
    }

    private var encouragement: String {
        switch point.effort.lowercased() {
        case "low", "medium":
            "轻装上阵，先把想法跑起来"
        case "high", "xhigh":
            "聪明和效率，今晚握个手"
        case "max", "ultra":
            "火力全开，难题交给它"
        default:
            "命运已经替你做了决定"
        }
    }
}
