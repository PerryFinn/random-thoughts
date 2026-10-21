import Foundation
import Observation

@MainActor
@Observable
final class CodexSessionStore {
    private struct Selection {
        var scan: CodexSessionScan?
        var ids: Set<String> = []
        var revision: UInt64 = 0
        var confirmedRevision: UInt64?
        var snapshot: CodexSessionSnapshot?
        var error: CodexSourceError?
    }

    private var selections: [ReportDay: Selection] = [:]
    private(set) var activeDay: ReportDay?
    private(set) var isConfirming = false
    private(set) var activity: CodexScanActivity = .reading
    private var pendingUnknown: (day: ReportDay, ids: Set<String>)?
    private var generation: UInt64 = 0
    private var confirmingDay: ReportDay?
    @ObservationIgnored private let access: any CodexSourceAccess
    @ObservationIgnored private let redact: @Sendable (String) throws -> String
    @ObservationIgnored private let record: (CodexScanEvent) -> Void
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationWorker: Task<CodexSessionSnapshot?, Never>?

    init(access: any CodexSourceAccess, redact: @escaping @Sendable (String) throws -> String,
         record: @escaping (CodexScanEvent) -> Void) {
        self.access = access
        self.redact = redact
        self.record = record
    }

    func scan(for day: ReportDay) -> CodexSessionScan? { selections[day]?.scan }
    func selectedIDs(for day: ReportDay) -> Set<String> { selections[day]?.ids ?? [] }
    func snapshot(for day: ReportDay) -> CodexSessionSnapshot? { selections[day]?.snapshot }
    var snapshotCount: Int { selections.values.filter { $0.snapshot != nil }.count }
    func error(for day: ReportDay) -> CodexSourceError? { selections[day]?.error }
    func needsConfirmation(for day: ReportDay) -> Bool {
        guard let selection = selections[day] else { return false }
        return selection.snapshot != nil && selection.confirmedRevision != selection.revision
    }

    func wait() async { await scanTask?.value; await confirmationTask?.value }

    func start(source: CodexSourceIdentity, day: ReportDay,
               completion: @escaping (CodexSessionScan?, CodexSourceError?) -> Void) {
        cancel()
        var selection = selections[day] ?? Selection()
        selection.scan = nil
        selection.ids = []
        selection.error = nil
        selection.revision += 1
        selections[day] = selection
        let expected = generation
        activeDay = day
        activity = .reading
        scanTask = Task {
            do {
                let scan = try await access.scan(source, day: day) { activity in
                    Task { @MainActor in
                        guard expected == self.generation, self.activeDay != nil else { return }
                        self.activity = activity
                    }
                }
                guard expected == generation, !Task.isCancelled else { return }
                activeDay = nil
                selections[day]?.scan = scan
                selections[day]?.ids = Set(scan.sessions.filter { $0.origin == .user }.map(\.id))
                record(CodexScanEvent(result: scan.isPartial ? .partial : .complete,
                                      candidates: scan.sessions.count + scan.failures.count,
                                      succeeded: scan.sessions.count, failed: scan.failures.count))
                completion(scan, nil)
            } catch {
                guard expected == generation, !Task.isCancelled else { return }
                activeDay = nil
                let failure = error as? CodexSourceError ?? .transportInterrupted
                selections[day]?.error = failure
                record(CodexScanEvent(result: .failure, candidates: 0, succeeded: 0, failed: 0))
                completion(nil, failure)
            }
        }
    }

    func select(_ ids: Set<String>, included: Bool, day: ReportDay) -> Bool {
        guard let scan = selections[day]?.scan, activeDay == nil, !isConfirming else { return false }
        let valid = Set(scan.sessions.map(\.id)).intersection(ids)
        if included {
            let unknown = Set(scan.sessions.filter { $0.origin == .unknown }.map(\.id)).intersection(valid)
                .subtracting(selectedIDs(for: day))
            if !unknown.isEmpty {
                pendingUnknown = (day, valid)
                return true
            }
            selections[day]?.ids.formUnion(valid)
        } else {
            selections[day]?.ids.subtract(valid)
        }
        selections[day]?.revision += 1
        return false
    }

    func acceptUnknown(day: ReportDay) {
        guard let pending = pendingUnknown, pending.day == day, selections[day]?.scan != nil else { return }
        selections[day]?.ids.formUnion(pending.ids)
        selections[day]?.revision += 1
        pendingUnknown = nil
    }

    func cancelUnknown() { pendingUnknown = nil }

    func confirm(day: ReportDay, completion: @escaping () -> Void) {
        guard let selection = selections[day], let scan = selection.scan, !selection.ids.isEmpty,
              activeDay == nil, !isConfirming else { return }
        let sessions = scan.sessions.filter { selection.ids.contains($0.id) }
        let expected = generation
        isConfirming = true
        confirmingDay = day
        let redact = redact
        let worker = Task.detached(priority: .userInitiated) { () -> CodexSessionSnapshot? in
                var failed = false
                func text(_ value: String) -> String {
                    do { return try redact(value) } catch { failed = true; return value }
                }
                func turn(_ value: CodexWorkTurn) -> CodexWorkTurn {
                    CodexWorkTurn(id: value.id, startedAt: value.startedAt, day: value.day,
                                  userText: text(value.userText), finalAnswer: value.finalAnswer.map(text))
                }
                var copies: [CodexCandidateSession] = []
                for session in sessions {
                    if Task.isCancelled { return nil }
                    copies.append(CodexCandidateSession(id: session.id, title: text(session.title),
                        workDirectory: session.workDirectory.map(text), origin: session.origin,
                        turns: session.turns.map(turn), background: session.background.map(turn)))
                }
                return CodexSessionSnapshot(day: day, sessions: copies, redactionFailed: failed)
        }
        confirmationWorker = worker
        confirmationTask = Task {
            let snapshot = await worker.value
            guard expected == generation, selections[day]?.revision == selection.revision, !Task.isCancelled, let snapshot else { return }
            isConfirming = false
            confirmingDay = nil
            confirmationWorker = nil
            selections[day]?.snapshot = snapshot
            selections[day]?.confirmedRevision = selection.revision
            let replacements = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            selections[day]?.scan = CodexSessionScan(sessions: scan.sessions.map { replacements[$0.id] ?? $0 },
                                                    failures: scan.failures, version: scan.version)
            completion()
        }
    }

    func cancel() {
        generation += 1
        if let activeDay {
            selections[activeDay]?.error = .cancelled
            record(CodexScanEvent(result: .cancelled, candidates: 0, succeeded: 0, failed: 0))
        }
        scanTask?.cancel()
        confirmationTask?.cancel()
        confirmationWorker?.cancel()
        confirmationWorker = nil
        activeDay = nil
        isConfirming = false
        confirmingDay = nil
        pendingUnknown = nil
    }

    func cancel(for day: ReportDay) {
        if activeDay == day || confirmingDay == day { cancel() }
    }

    func sourceChanged() {
        cancel()
        for day in selections.keys {
            selections[day]?.scan = nil
            selections[day]?.ids = []
            selections[day]?.error = nil
            selections[day]?.revision += 1
        }
    }

    func clear(timeZone: String? = nil) {
        cancel()
        if let timeZone { selections = selections.filter { $0.key.timeZoneIdentifier != timeZone } }
        else { selections.removeAll() }
    }
}
