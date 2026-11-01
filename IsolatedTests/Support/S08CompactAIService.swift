import Foundation
import Testing
@testable import random_thoughts

// A deterministic external-service substitute, never a model reliability test.
// The observed left subtree keeps its source summaries byte for byte. Dense
// synthetic responses on the right make the real executor traverse all layers.
actor S08CompactAIService {
    struct Exchange: Sendable {
        let request: AIRequest
        let response: String
    }
    private(set) var exchanges: [Exchange] = []
    private let steps: [String: (id: Int, layer: Int)]

    init(plan: ReportBatchPlan) {
        var steps = Dictionary(uniqueKeysWithValues: plan.extraction.map { ($0.input, (id: $0.id, layer: 0)) })
        for (layer, nodes) in plan.mergeLayers.enumerated() {
            for node in nodes { steps[node.input] = (id: node.id, layer: layer + 1) }
        }
        self.steps = steps
    }

    func execute(_ request: AIRequest) async throws -> String {
        if case .composeReport = request.intent {
            exchanges.append(.init(request: request, response: syntheticReportPayload))
            return syntheticReportPayload
        }
        let step = try #require(steps[request.input])
        let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
        let fragments = input["fragments"] as! [[String: Any]]
        let nodes = try request.additionalInputs.map { try JSONDecoder().decode(S08CompactNode.self, from: Data($0.utf8)) }
        let turns = fragments.isEmpty ? nodes.flatMap { $0.facts.flatMap(\.turns) }
            : fragments.map { $0["association"] as! String }
        let target = turns.allSatisfy { Int($0.split(separator: "/")[0])! <= 9 }
        let covered = fragments.isEmpty ? input["upstream"] as! [Int] : fragments.map { $0["id"] as! Int }
        var groups: [[String: Any]] = []
        if target, fragments.isEmpty {
            for node in nodes {
                for group in node.groups {
                    groups.append(["references": [node.id], "status": group.status.rawValue,
                        "facts": group.facts.map { ["turns": $0.turns, "summary": $0.summary] }])
                }
            }
        } else if target {
            for fragment in fragments {
                let answer = try #require(fragment["finalAnswer"] as? String)
                let blocker = " The shared synthetic schema mismatch blocks integrating these rules."
                var facts: [[String: Any]] = [["turns": [fragment["association"] as! String],
                    "summary": answer.replacingOccurrences(of: blocker, with: "")]]
                if answer.contains(blocker) {
                    facts.append(["turns": [fragment["association"] as! String],
                        "summary": "The shared synthetic schema mismatch blocks integrating these rules; affected scope unspecified."])
                }
                groups.append(["references": [fragment["id"] as! Int],
                    "status": fragment["session"] as! Int == 1 ? "confirmed" : "unconfirmed", "facts": facts])
            }
        } else {
            let summary = step.layer < 3 ? String(repeating: " factual", count: 1_100) : "Other synthetic drafts remain unconfirmed."
            groups = [["references": covered, "status": "unconfirmed",
                       "facts": [["turns": Array(Set(turns)).sorted(), "summary": summary]]]]
        }
        let response = String(decoding: try JSONSerialization.data(withJSONObject:
            ["covered": covered, "noRelevantContent": false, "groups": groups], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        exchanges.append(.init(request: request, response: response))
        return response
    }
}

extension S08CompactAIService: AIServiceAccess {}

struct S08CompactNode: Decodable {
    struct Group: Decodable {
        let status: ReportFactPayload.Fact.Status
        let facts: [ReportFactPayload.Evidence]
    }
    let id: Int
    let groups: [Group]
    let noRelevantContent: Bool
    let completeTurns: [String]
    var facts: [ReportFactPayload.Fact] {
        groups.flatMap { group in
            group.facts.map { .init(references: [id], turns: $0.turns, status: group.status, summary: $0.summary) }
        }
    }
}
