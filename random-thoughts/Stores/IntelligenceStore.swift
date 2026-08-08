import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class IntelligenceStore {
    static let refreshInterval: TimeInterval = 30 * 60
    static let selectionLimit = 8

    private(set) var points: [IntelligencePoint] = []
    private(set) var selectedPointIDs: Set<String> = []
    private(set) var sourceUpdatedAt: Date?
    private(set) var history: [IntelligenceHistorySnapshot] = []
    private(set) var lastRefreshAt: Date?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: IntelligenceService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasSavedSelection: Bool

    private enum Keys {
        static let selectedPointIDs = "selectedPointIDs"
        static let cachedResponse = "cachedIntelligenceResponse"
        static let lastRefreshAt = "lastIntelligenceRefreshAt"
    }

    init(
        service: IntelligenceService = IntelligenceService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults

        if let savedIDs = defaults.array(forKey: Keys.selectedPointIDs) as? [String] {
            selectedPointIDs = Set(savedIDs)
            hasSavedSelection = true
        } else {
            hasSavedSelection = false
        }

        if let cachedData = defaults.data(forKey: Keys.cachedResponse),
           let cachedResponse = try? JSONDecoder().decode(IntelligenceResponse.self, from: cachedData) {
            apply(cachedResponse)
        }

        lastRefreshAt = defaults.object(forKey: Keys.lastRefreshAt) as? Date
    }

    var selectedPoints: [IntelligencePoint] {
        points.filter { selectedPointIDs.contains($0.id) }
    }

    var hasReachedSelectionLimit: Bool {
        selectedPointIDs.count >= Self.selectionLimit
    }

    var modelNames: [String] {
        var seen = Set<String>()
        return points.compactMap { point in
            seen.insert(point.model).inserted ? point.model : nil
        }
    }

    func iqHistory(for point: IntelligencePoint) -> [IntelligenceIQHistorySample] {
        var iqByDate: [Date: Double] = [:]

        for snapshot in history {
            guard let date = Self.parseISO8601(snapshot.at),
                  let historicalPoint = snapshot.points.first(where: {
                      $0.model == point.model && $0.effort == point.effort
                  }) else {
                continue
            }

            iqByDate[date] = historicalPoint.iq
        }

        if let sourceUpdatedAt {
            iqByDate[sourceUpdatedAt] = point.iq
        }

        return iqByDate
            .map { IntelligenceIQHistorySample(at: $0.key, iq: $0.value) }
            .sorted { $0.at < $1.at }
    }

    func iqChange24Hours(for point: IntelligencePoint) -> Double? {
        guard let sourceUpdatedAt else { return nil }
        let targetDate = sourceUpdatedAt.addingTimeInterval(-Self.trendInterval)

        let closestSnapshot = history.compactMap { snapshot -> (Date, IntelligenceHistoryPoint)? in
            guard let date = Self.parseISO8601(snapshot.at),
                  let historicalPoint = snapshot.points.first(where: {
                      $0.model == point.model && $0.effort == point.effort
                  }) else {
                return nil
            }

            return (date, historicalPoint)
        }
        .min { lhs, rhs in
            abs(lhs.0.timeIntervalSince(targetDate)) < abs(rhs.0.timeIntervalSince(targetDate))
        }

        guard let closestSnapshot,
              abs(closestSnapshot.0.timeIntervalSince(targetDate)) <= Self.trendTolerance else {
            return nil
        }

        return point.iq - closestSnapshot.1.iq
    }

    func comparisonWithNextLowerEffort(
        for point: IntelligencePoint
    ) -> IntelligencePointComparison? {
        guard let currentRank = Self.effortRanks[point.effort.lowercased()] else { return nil }

        let baseline = points
            .filter { candidate in
                guard candidate.model == point.model,
                      let candidateRank = Self.effortRanks[candidate.effort.lowercased()] else {
                    return false
                }
                return candidateRank < currentRank
            }
            .max { lhs, rhs in
                let lhsRank = Self.effortRanks[lhs.effort.lowercased()] ?? -1
                let rhsRank = Self.effortRanks[rhs.effort.lowercased()] ?? -1
                return lhsRank < rhsRank
            }

        guard let baseline else { return nil }

        return IntelligencePointComparison(
            baselineEffort: baseline.effort,
            iqDelta: point.iq - baseline.iq,
            priceDeltaUSD: Self.difference(point.averagePriceUSD, baseline.averagePriceUSD),
            minutesDelta: Self.difference(point.averageMinutes, baseline.averageMinutes)
        )
    }

    func confidenceWarning(for point: IntelligencePoint) -> IntelligenceConfidenceWarning? {
        let sampleCounts = [point.validTasks, point.priceSamples, point.durationSamples]
            .compactMap { $0 }

        if let minimumSampleCount = sampleCounts.min(),
           minimumSampleCount < Self.minimumReliableSampleCount {
            return .lowSample(minimumSampleCount)
        }

        if let validTasks = point.validTasks,
           validTasks > 0 {
            let coverageCandidates = [
                (metric: "成本数据", samples: point.priceSamples),
                (metric: "耗时数据", samples: point.durationSamples)
            ]
            .compactMap { candidate -> (metric: String, samples: Int, ratio: Double)? in
                guard let samples = candidate.samples else { return nil }
                return (
                    metric: candidate.metric,
                    samples: samples,
                    ratio: Double(samples) / Double(validTasks)
                )
            }

            if let lowestCoverage = coverageCandidates.min(by: { $0.ratio < $1.ratio }),
               lowestCoverage.ratio < Self.minimumCoverageRatio {
                return .lowCoverage(
                    metric: lowestCoverage.metric,
                    available: lowestCoverage.samples,
                    total: validTasks
                )
            }
        }

        if let incompleteCostSamples = point.incompleteCostSamples,
           incompleteCostSamples > 0 {
            return .incompleteCost(incompleteCostSamples)
        }

        return nil
    }

    func points(for model: String) -> [IntelligencePoint] {
        points.filter { $0.model == model }
    }

    func isSelected(_ point: IntelligencePoint) -> Bool {
        selectedPointIDs.contains(point.id)
    }

    func canSelect(_ point: IntelligencePoint) -> Bool {
        isSelected(point) || !hasReachedSelectionLimit
    }

    func setSelected(_ isSelected: Bool, point: IntelligencePoint) {
        if isSelected {
            guard canSelect(point) else { return }
            selectedPointIDs.insert(point.id)
        } else {
            selectedPointIDs.remove(point.id)
        }
        saveSelection()
    }

    func selectAll() {
        selectedPointIDs = Set(points.prefix(Self.selectionLimit).map(\.id))
        saveSelection()
    }

    func clearSelection() {
        selectedPointIDs.removeAll()
        saveSelection()
    }

    func startUpdating() {
        guard refreshTask == nil else { return }

        AppTelemetry.refresh.info(
            "Automatic refresh started; intervalSeconds=\(Int(Self.refreshInterval), privacy: .public)"
        )

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()

                do {
                    try await Task.sleep(for: .seconds(Self.refreshInterval))
                } catch {
                    return
                }
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            AppTelemetry.refresh.debug("Refresh skipped because one is already active")
            return
        }

        isRefreshing = true
        AppTelemetry.refresh.debug("Refresh started")
        defer { isRefreshing = false }

        do {
            let response = try await service.fetch()
            apply(response)
            lastRefreshAt = Date()
            errorMessage = nil

            if let encoded = try? JSONEncoder().encode(response) {
                defaults.set(encoded, forKey: Keys.cachedResponse)
            }
            defaults.set(lastRefreshAt, forKey: Keys.lastRefreshAt)
            AppTelemetry.refresh.info(
                "Refresh succeeded; pointCount=\(self.points.count, privacy: .public)"
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppTelemetry.refresh.error(
                "Refresh failed; cachedPointCount=\(self.points.count, privacy: .public)"
            )
        }
    }

    private func apply(_ response: IntelligenceResponse) {
        points = response.points
        sourceUpdatedAt = response.sourceUpdatedAt.flatMap(ISO8601DateFormatter().date(from:))
        history = response.history ?? []
        reconcileSavedSelection()

        guard !hasSavedSelection, !points.isEmpty else { return }
        let defaultPoint = points.first {
            $0.model == "gpt-5.6-sol" && $0.effort == "max"
        } ?? points.max(by: { $0.iq < $1.iq })

        if let defaultPoint {
            selectedPointIDs = [defaultPoint.id]
            saveSelection()
        }
    }

    private func reconcileSavedSelection() {
        guard hasSavedSelection else { return }

        let reconciledIDs = Set(
            points
                .filter { selectedPointIDs.contains($0.id) }
                .prefix(Self.selectionLimit)
                .map(\.id)
        )

        guard reconciledIDs != selectedPointIDs else { return }
        selectedPointIDs = reconciledIDs
        saveSelection()
    }

    private func saveSelection() {
        hasSavedSelection = true
        defaults.set(Array(selectedPointIDs).sorted(), forKey: Keys.selectedPointIDs)
    }

    private static let trendInterval: TimeInterval = 24 * 60 * 60
    private static let trendTolerance: TimeInterval = 6 * 60 * 60
    private static let minimumReliableSampleCount = 30
    private static let minimumCoverageRatio = 0.9
    private static let effortRanks = Dictionary(
        uniqueKeysWithValues: ["low", "medium", "high", "xhigh", "max", "ultra"]
            .enumerated()
            .map { ($0.element, $0.offset) }
    )

    private static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }
}
