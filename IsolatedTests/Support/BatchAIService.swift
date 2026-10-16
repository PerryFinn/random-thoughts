import Foundation
@testable import random_thoughts

actor BatchAIService: AIServiceAccess {
    enum Mode: String, Sendable {
        case compact, dense, missingCoverage, duplicateCoverage, invalidReference, wrongTurn
        case partialCompletion, oversized, malformed, duplicateFields, eraseOnMerge, unreduced, noRelevant, privateSummary
    }
    private(set) var requests: [AIRequest] = []
    private(set) var cancelled = 0
    private let mode: Mode
    private var holds: Bool
    private var pending: [Int: CheckedContinuation<String, any Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    init(mode: Mode = .compact, holds: Bool = false) { self.mode = mode; self.holds = holds }
    func waitForRequests(_ count: Int) async {
        if requests.count < count { await withCheckedContinuation { observers.append((count, $0)) } }
    }
    func release(_ index: Int, failure: AIRequestError? = nil) {
        guard let continuation = pending.removeValue(forKey: index) else { return }
        if let failure { continuation.resume(throwing: failure) }
        else {
            do { continuation.resume(returning: try response(requests[index])) }
            catch { continuation.resume(throwing: error) }
        }
    }
    func releaseAll() {
        holds = false
        for index in pending.keys.sorted() { release(index) }
    }
    private func cancel(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { return }
        cancelled += 1; continuation.resume(throwing: CancellationError())
    }
    private func notify() {
        let ready = observers.filter { $0.0 <= requests.count }
        observers.removeAll { $0.0 <= requests.count }
        ready.forEach { $0.1.resume() }
    }
    func execute(_ request: AIRequest) async throws -> String {
        let index = requests.count
        requests.append(request)
        if holds {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else { pending[index] = continuation }
                    notify()
                }
            } onCancel: { Task { await self.cancel(index) } }
        }
        notify()
        return try response(request)
    }
    private func response(_ request: AIRequest) throws -> String {
        switch request.intent {
        case .composeReport:
            return mode == .noRelevant ? #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"# : syntheticReportPayload
        case .probe: throw AIRequestError.parameters
        case .extractFacts, .mergeFacts:
            let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
            let fragments = input["fragments"] as? [[String: Any]] ?? []
            let isMerge = fragments.isEmpty
            var ids = fragments.isEmpty ? input["upstream"] as! [Int] : fragments.map { $0["id"] as! Int }
            var turns = Set(fragments.map { "\($0["session"] as! Int)/\($0["order"] as! Int)" })
            for block in request.additionalInputs {
                let node = try JSONSerialization.jsonObject(with: Data(block.utf8)) as! [String: Any]
                for fact in node["facts"] as! [[String: Any]] { turns.formUnion(fact["turns"] as! [String]) }
            }
            let visible = input["visibleBudget"] as! Int
            let padded = mode == .dense || mode == .eraseOnMerge || mode == .unreduced
            let compactFirstGroup = mode == .unreduced && !isMerge && (ids.first ?? 0) <= 3
            let expand = padded && !compactFirstGroup && (!isMerge || mode == .unreduced)
            var summary = expand ? String(repeating: " factual", count: max(1, visible - 220)) : "合成进展，整轮结果尚待全部片段整合。"
            if mode == .privateSummary { summary = "INTERMEDIATE_PRIVATE_31 \(request.credential)" }
            var references = ids
            if mode == .invalidReference { references = [-999] }
            if mode == .wrongTurn { turns = ["999/999"] }
            if mode == .missingCoverage { ids = Array(ids.dropLast()) }
            if mode == .duplicateCoverage { ids += ids.prefix(1) }
            if mode == .malformed { return "not a fact payload" }
            if mode == .oversized { return String(repeating: " TOO_LARGE", count: visible * 2) }
            if mode == .duplicateFields { return "{\"covered\":[],\"covered\":[],\"facts\":[],\"noRelevantContent\":true}" }
            let erased = mode == .eraseOnMerge && isMerge || mode == .noRelevant
            let facts: [[String: Any]] = erased ? [] : [["references": references, "turns": turns.sorted(),
                "status": mode == .partialCompletion ? "confirmed" : "uncertain", "summary": summary]]
            return String(decoding: try JSONSerialization.data(withJSONObject: ["covered": ids,
                "noRelevantContent": facts.isEmpty, "facts": facts], options: [.sortedKeys]), as: UTF8.self)
        }
    }
}
