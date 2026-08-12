import Foundation

enum ModelRecommendationStrategy: String, CaseIterable, Identifiable, Sendable {
    case sweetSpot
    case smartest
    case cheapest
    case fastest

    var id: Self { self }

    var title: String {
        switch self {
        case .sweetSpot:
            "甜点档"
        case .smartest:
            "最聪明"
        case .cheapest:
            "最省钱"
        case .fastest:
            "最快"
        }
    }

    var systemImage: String {
        switch self {
        case .sweetSpot:
            "sparkles"
        case .smartest:
            "brain.head.profile.fill"
        case .cheapest:
            "banknote.fill"
        case .fastest:
            "bolt.fill"
        }
    }

    var help: String {
        switch self {
        case .sweetSpot:
            "兼顾智能、成本和速度"
        case .smartest:
            "选择 IQ 最高的一档"
        case .cheapest:
            "选择平均成本最低的一档"
        case .fastest:
            "选择平均耗时最短的一档"
        }
    }
}

struct ModelRecommendation: Equatable, Sendable {
    let strategy: ModelRecommendationStrategy
    let point: IntelligencePoint
    let reason: String
}

enum ModelRecommender {
    static func recommend(
        from points: [IntelligencePoint],
        strategy: ModelRecommendationStrategy
    ) -> ModelRecommendation? {
        guard !points.isEmpty else { return nil }

        let point: IntelligencePoint?
        switch strategy {
        case .sweetSpot:
            point = sweetSpot(from: points)
        case .smartest:
            point = points.max(by: isLessIntelligent)
        case .cheapest:
            point = points
                .filter { $0.averagePriceUSD?.isFinite == true }
                .min(by: isCheaper)
        case .fastest:
            point = points
                .filter { $0.averageMinutes?.isFinite == true }
                .min(by: isFaster)
        }

        guard let point else { return nil }
        return ModelRecommendation(
            strategy: strategy,
            point: point,
            reason: reason(for: point, strategy: strategy)
        )
    }

    private static func sweetSpot(from points: [IntelligencePoint]) -> IntelligencePoint? {
        let completePoints = points.filter {
            $0.iq.isFinite
                && $0.averagePriceUSD?.isFinite == true
                && $0.averageMinutes?.isFinite == true
        }

        guard !completePoints.isEmpty else {
            return points.max(by: isLessIntelligent)
        }

        let iqRange = valueRange(completePoints.map(\.iq))
        let priceRange = valueRange(completePoints.compactMap(\.averagePriceUSD))
        let durationRange = valueRange(completePoints.compactMap(\.averageMinutes))

        return completePoints.max { lhs, rhs in
            let lhsScore = sweetSpotScore(
                for: lhs,
                iqRange: iqRange,
                priceRange: priceRange,
                durationRange: durationRange
            )
            let rhsScore = sweetSpotScore(
                for: rhs,
                iqRange: iqRange,
                priceRange: priceRange,
                durationRange: durationRange
            )

            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return isLessIntelligent(lhs, rhs)
        }
    }

    private static func sweetSpotScore(
        for point: IntelligencePoint,
        iqRange: ClosedRange<Double>,
        priceRange: ClosedRange<Double>,
        durationRange: ClosedRange<Double>
    ) -> Double {
        guard let price = point.averagePriceUSD,
              let duration = point.averageMinutes else {
            return -.infinity
        }

        let intelligence = normalized(point.iq, in: iqRange)
        let affordability = 1 - normalized(price, in: priceRange)
        let speed = 1 - normalized(duration, in: durationRange)
        return intelligence * 0.55 + affordability * 0.3 + speed * 0.15
    }

    private static func valueRange(_ values: [Double]) -> ClosedRange<Double> {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        return minimum...maximum
    }

    private static func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 1 }
        return (value - range.lowerBound) / span
    }

    nonisolated private static func isLessIntelligent(
        _ lhs: IntelligencePoint,
        _ rhs: IntelligencePoint
    ) -> Bool {
        if lhs.iq != rhs.iq { return lhs.iq < rhs.iq }
        return lhs.id > rhs.id
    }

    nonisolated private static func isCheaper(
        _ lhs: IntelligencePoint,
        _ rhs: IntelligencePoint
    ) -> Bool {
        let lhsPrice = lhs.averagePriceUSD ?? .infinity
        let rhsPrice = rhs.averagePriceUSD ?? .infinity
        if lhsPrice != rhsPrice { return lhsPrice < rhsPrice }
        return isPreferredTieBreaker(lhs, rhs)
    }

    nonisolated private static func isFaster(
        _ lhs: IntelligencePoint,
        _ rhs: IntelligencePoint
    ) -> Bool {
        let lhsDuration = lhs.averageMinutes ?? .infinity
        let rhsDuration = rhs.averageMinutes ?? .infinity
        if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
        return isPreferredTieBreaker(lhs, rhs)
    }

    nonisolated private static func isPreferredTieBreaker(
        _ lhs: IntelligencePoint,
        _ rhs: IntelligencePoint
    ) -> Bool {
        if lhs.iq != rhs.iq { return lhs.iq > rhs.iq }
        return lhs.id < rhs.id
    }

    private static func reason(
        for point: IntelligencePoint,
        strategy: ModelRecommendationStrategy
    ) -> String {
        switch strategy {
        case .sweetSpot:
            if point.averagePriceUSD == nil || point.averageMinutes == nil {
                return "成本或耗时数据不足，先替你选择了当前 IQ 最高的一档。"
            }
            return "综合 IQ、平均成本与耗时后，它是当前选择里最均衡的一档。"
        case .smartest:
            return "IQ \(point.iq.formatted(.number.precision(.fractionLength(1))))，是当前选择里的最高值。"
        case .cheapest:
            guard let price = point.averagePriceUSD else { return "暂无可用的成本数据。" }
            let value = String(
                format: "$%.2f",
                locale: Locale(identifier: "en_US_POSIX"),
                price
            )
            return "平均成本 \(value)，是当前选择里的最低值。"
        case .fastest:
            guard let minutes = point.averageMinutes else { return "暂无可用的耗时数据。" }
            let value = minutes.formatted(.number.precision(.fractionLength(1)))
            return "平均耗时 \(value) 分钟，是当前选择里的最短值。"
        }
    }
}
