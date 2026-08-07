import Foundation
import Observation

@MainActor
@Observable
final class IntelligenceStore {
    static let refreshInterval: TimeInterval = 30 * 60
    static let selectionLimit = 8

    private(set) var points: [IntelligencePoint] = []
    private(set) var selectedPointIDs: Set<String> = []
    private(set) var sourceUpdatedAt: Date?
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
        guard !isRefreshing else { return }
        isRefreshing = true
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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ response: IntelligenceResponse) {
        points = response.points
        sourceUpdatedAt = response.sourceUpdatedAt.flatMap(ISO8601DateFormatter().date(from:))
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
}
