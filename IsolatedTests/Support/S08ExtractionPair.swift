import Foundation
import Testing
@testable import random_thoughts

// The two complete turns that produced L03's observed association failure.
// This is a component fixture, never a replacement for full S08 acceptance.
@MainActor
enum S08ExtractionPair {
    static func makePlan(from original: ReportBatchPlan) throws -> ReportBatchPlan {
        let source = try #require(original.extraction.first { $0.id == 6 })
        let fragments = Array(source.fragments.prefix(2))
        try #require(source.fragments.map(\.id) == [22, 23, 24, 25])
        try #require(fragments.map(\.association) == ["7/1", "7/2"] && fragments.allSatisfy { $0.parts == 1 })
        var input = try #require(JSONSerialization.jsonObject(with: Data(source.input.utf8)) as? [String: Any])
        input["fragments"] = try #require(input["fragments"] as? [[String: Any]]).filter {
            [22, 23].contains($0["id"] as? Int ?? -1)
        }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: input,
            options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        let step = ReportBatchNodePlan(id: source.id, upstream: [], fragments: fragments,
            input: text, auxiliaryClipped: source.auxiliaryClipped)
        return .init(prepared: original.prepared, extraction: [step], mergeLayers: [],
            visibleLimit: original.visibleLimit, factInstruction: original.factInstruction, factSchema: original.factSchema,
            factBudget: original.factBudget, finalSchema: original.finalSchema, finalBudget: original.finalBudget)
    }
}
