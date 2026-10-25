import Foundation
@testable import random_thoughts

actor ControlledAIService {
    private(set) var requests: [AIRequest] = []
    private var results: [Result<String, any Error>] = []
    private var holdsNext = false
    private var held: CheckedContinuation<String, any Error>?
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func enqueue(_ result: Result<String, AIRequestError>) { results.append(result.mapError { $0 as any Error }) }
    func enqueueFailure(_ failure: AIRequestFailure) { results.append(.failure(failure)) }
    func holdNextResponse() { holdsNext = true }
    func waitForRequest(_ number: Int = 1) async {
        if requests.count < number { await withCheckedContinuation { observers.append((number, $0)) } }
    }
    func release(_ result: Result<String, AIRequestError>) { held?.resume(with: result.mapError { $0 as any Error }); held = nil }
    func execute(_ request: AIRequest) async throws -> String {
        requests.append(request)
        let ready = observers.filter { $0.0 <= requests.count }
        observers.removeAll { $0.0 <= requests.count }
        if holdsNext {
            holdsNext = false
            return try await withCheckedThrowingContinuation {
                held = $0
                ready.forEach { $0.1.resume() }
            }
        }
        ready.forEach { $0.1.resume() }
        if !results.isEmpty { return try results.removeFirst().get() }
        return request.schema == nil ? "OK" : #"{"ok":"OK"}"#
    }
}

extension ControlledAIService: AIServiceAccess {}
