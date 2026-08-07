import Foundation

struct IntelligencePoint: Codable, Identifiable, Hashable, Sendable {
    let model: String
    let effort: String
    let iq: Double
    let averagePriceUSD: Double?
    let averageMinutes: Double?
    let runs24h: Int?
    let latestGradedAt: String?

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
    }
}

struct IntelligenceResponse: Codable, Sendable {
    let sourceUpdatedAt: String?
    let points: [IntelligencePoint]

    private enum CodingKeys: String, CodingKey {
        case sourceUpdatedAt = "source_updated_at"
        case points
    }
}
