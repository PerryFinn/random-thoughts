import Foundation

enum ModelRoulette {
    static func pick(
        from points: [IntelligencePoint],
        excluding excludedID: IntelligencePoint.ID? = nil,
        randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> IntelligencePoint? {
        guard !points.isEmpty else { return nil }

        let candidates: [IntelligencePoint]
        if points.count > 1, let excludedID {
            candidates = points.filter { $0.id != excludedID }
        } else {
            candidates = points
        }

        return candidates[randomIndex(candidates.indices)]
    }
}
