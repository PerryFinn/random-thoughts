import Foundation

struct IntelligencePoint: Codable, Identifiable, Hashable, Sendable {
    let model: String
    let effort: String
    let iq: Double
    let averagePriceUSD: Double?
    let averageMinutes: Double?
    let runs24h: Int?
    let latestGradedAt: String?
    let validTasks: Int?
    let priceSamples: Int?
    let durationSamples: Int?
    let incompleteCostSamples: Int?

    init(
        model: String,
        effort: String,
        iq: Double,
        averagePriceUSD: Double?,
        averageMinutes: Double?,
        runs24h: Int?,
        latestGradedAt: String?,
        validTasks: Int? = nil,
        priceSamples: Int? = nil,
        durationSamples: Int? = nil,
        incompleteCostSamples: Int? = nil
    ) {
        self.model = model
        self.effort = effort
        self.iq = iq
        self.averagePriceUSD = averagePriceUSD
        self.averageMinutes = averageMinutes
        self.runs24h = runs24h
        self.latestGradedAt = latestGradedAt
        self.validTasks = validTasks
        self.priceSamples = priceSamples
        self.durationSamples = durationSamples
        self.incompleteCostSamples = incompleteCostSamples
    }

    var id: String { "\(model)|\(effort)" }

    var cardModelName: String {
        let prefix = "gpt-5.6-"

        if model.hasPrefix(prefix) {
            return String(model.dropFirst(prefix.count)).capitalized
        } else if model.hasPrefix("gpt-") {
            return model.uppercased()
        } else {
            return model
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    var cardTitle: String {
        "\(cardModelName) \(effort)"
    }

    var groupTitle: String {
        model.hasPrefix("gpt-5.6-") ? "GPT \(cardModelName)" : cardModelName
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case averagePriceUSD = "average_price_usd"
        case averageMinutes = "average_minutes"
        case runs24h = "runs_24h"
        case latestGradedAt = "latest_graded_at"
        case validTasks = "valid_tasks"
        case priceSamples = "price_samples"
        case durationSamples = "duration_samples"
        case incompleteCostSamples = "incomplete_cost_samples"
    }
}

struct IntelligenceResponse: Codable, Sendable {
    let sourceUpdatedAt: String?
    let points: [IntelligencePoint]
    let history: [IntelligenceHistorySnapshot]?

    init(
        sourceUpdatedAt: String?,
        points: [IntelligencePoint],
        history: [IntelligenceHistorySnapshot]? = nil
    ) {
        self.sourceUpdatedAt = sourceUpdatedAt
        self.points = points
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case sourceUpdatedAt = "source_updated_at"
        case points
        case history
    }
}

struct IntelligenceHistorySnapshot: Codable, Sendable {
    let at: String
    let points: [IntelligenceHistoryPoint]
}

struct IntelligenceHistoryPoint: Codable, Sendable {
    let model: String
    let effort: String
    let iq: Double
}

struct IntelligencePointComparison: Equatable, Sendable {
    let baselineEffort: String
    let iqDelta: Double
    let priceDeltaUSD: Double?
    let minutesDelta: Double?
}

enum IntelligenceConfidenceWarning: Equatable, Sendable {
    case lowSample(Int)
    case incompleteCost(Int)

    var title: String {
        switch self {
        case .lowSample:
            "样本较少"
        case .incompleteCost:
            "成本待补"
        }
    }

    var detail: String {
        switch self {
        case let .lowSample(count):
            "当前最少只有 \(count) 个有效样本，指标波动可能较大"
        case let .incompleteCost(count):
            "有 \(count) 次运行的成本数据不完整，平均成本已排除这些样本"
        }
    }
}
