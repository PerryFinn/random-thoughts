import Foundation
@testable import random_thoughts

actor BatchAIService {
    enum Mode: String, Sendable {
        case compact, dense, missingCoverage, duplicateCoverage, invalidReference, wrongTurn
        case partialCompletion, numericTurn
        case oversized, malformed, duplicateFields, eraseOnMerge, unreduced, noRelevant, privateSummary
        case emptyReference, duplicateReference, emptyTurns, duplicateTurns, emptySummary, wrongRelevance
    }
    private(set) var requests: [AIRequest] = []
    private(set) var cancelled = 0
    private let mode: Mode
    private var holds: Bool
    private var heldStage: ReportGenerationStage?
    private let ignoresCancellation: Bool
    private var pending: [Int: CheckedContinuation<String, any Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    init(mode: Mode = .compact, holds: Bool = false, ignoresCancellation: Bool = false) {
        self.mode = mode; self.holds = holds; self.ignoresCancellation = ignoresCancellation
    }
    func hold(stage: ReportGenerationStage) { holds = true; heldStage = stage }
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
        if ignoresCancellation { return }
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
        let stage: ReportGenerationStage? = switch request.intent {
        case .extractFacts: .extracting
        case .mergeFacts: .merging
        case .composeReport: .composing
        case .probe: nil
        }
        if holds, let stage, heldStage == nil || heldStage == stage {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled && !ignoresCancellation { continuation.resume(throwing: CancellationError()) }
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
        case .probe(let stage): return stage == .structured ? #"{"ok":"OK"}"# : "OK"
        case .extractFacts, .mergeFacts:
            let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
            let fragments = input["fragments"] as? [[String: Any]] ?? []
            let isMerge = fragments.isEmpty
            var ids = fragments.isEmpty ? input["upstream"] as! [Int] : fragments.map { $0["id"] as! Int }
            var turns = Set(fragments.map { "\($0["session"] as! Int)/\($0["order"] as! Int)" })
            for block in request.additionalInputs {
                let node = try JSONSerialization.jsonObject(with: Data(block.utf8)) as! [String: Any]
                for group in node["groups"] as! [[String: Any]] {
                    for fact in group["facts"] as! [[String: Any]] { turns.formUnion(fact["turns"] as! [String]) }
                }
            }
            let visible = input["visibleBudget"] as! Int
            let padded = [.dense, .eraseOnMerge, .unreduced].contains(mode)
            let compactFirstGroup = mode == .unreduced && !isMerge && (ids.first ?? 0) <= 3
            let expand = padded && !compactFirstGroup && (!isMerge || mode == .unreduced)
            var summary = expand ? String(repeating: " factual", count: max(1, visible - 220)) : "合成进展，整轮结果尚待全部片段整合。"
            if mode == .privateSummary { summary = "INTERMEDIATE_PRIVATE_31 \(request.credential)" }
            var references = ids
            if mode == .invalidReference { references = [-999] }
            if mode == .emptyReference { references = [] }
            if mode == .duplicateReference { references += references.prefix(1) }
            if mode == .wrongTurn { turns = ["999/999"] }
            if mode == .emptyTurns { turns = [] }
            if mode == .emptySummary { summary = " \n\t" }
            if mode == .numericTurn { turns = Set(references.map(String.init)) }
            if mode == .missingCoverage { ids = Array(ids.dropLast()) }
            if mode == .duplicateCoverage { ids += ids.prefix(1) }
            if mode == .malformed { return "not a fact payload" }
            if mode == .oversized { return String(repeating: " TOO_LARGE", count: visible * 2) }
            if mode == .duplicateFields { return "{\"covered\":[],\"covered\":[],\"groups\":[],\"noRelevantContent\":true}" }
            let erased = mode == .eraseOnMerge && isMerge || mode == .noRelevant
            let confirmed = mode == .partialCompletion
            let turnList = turns.sorted() + (mode == .duplicateTurns ? Array(turns.sorted().prefix(1)) : [])
            let groups: [[String: Any]] = erased ? [] : [["references": references,
                "status": confirmed ? "confirmed" : "uncertain", "facts": [["turns": turnList, "summary": summary]]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: ["covered": ids,
                "noRelevantContent": mode == .wrongRelevance || groups.isEmpty, "groups": groups], options: [.sortedKeys]), as: UTF8.self)
        }
    }
}

extension BatchAIService: AIServiceAccess {}
