import Foundation
import Observation

@MainActor
@Observable
final class CodexDataSourceStore {
    private(set) var saved = CodexDataSourceSettings()
    private(set) var edit = CodexDataSourceConfiguration()
    private(set) var status: CodexSourceStatus = .unchecked
    private(set) var isChecking = false
    private(set) var error: CodexSourceError?
    private(set) var storageError: ReportStorageError?
    private(set) var revision: UInt64 = 0
    var hasEdits: Bool { edit != saved.configuration }

    @ObservationIgnored private let storage: any DailyReportStorage
    @ObservationIgnored private let access: any CodexSourceAccess
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sourceChanged: (UInt64) -> Void
    @ObservationIgnored private let record: (CodexCheckEvent) -> Void
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    private var checkRevision: UInt64 = 0

    init(storage: any DailyReportStorage, access: any CodexSourceAccess, now: @escaping () -> Date,
         sourceChanged: @escaping (UInt64) -> Void, record: @escaping (CodexCheckEvent) -> Void) {
        self.storage = storage
        self.access = access
        self.now = now
        self.sourceChanged = sourceChanged
        self.record = record
    }

    func restore(_ settings: CodexDataSourceSettings) {
        saved = settings
        edit = settings.configuration
        status = .unchecked
    }

    func setEdit(_ configuration: CodexDataSourceConfiguration) { edit = configuration }
    func revert() { edit = saved.configuration; storageError = nil }
    func waitForCheck() async { await checkTask?.value }

    func save(rediscover: Bool, after previous: Task<Void, Never>?, completion: @escaping (Bool) -> Void) -> Task<Void, Never> {
        let configuration = edit
        storageError = nil
        return Task {
            await previous?.value
            var selection = await access.resolve(configuration, rediscover: rediscover)
            if selection.settings.identity == saved.identity {
                selection.settings.lastSuccessfulCheck = saved.lastSuccessfulCheck
                selection.settings.version = saved.version
            }
            do {
                try await storage.saveCodexSource(selection.settings)
                cancelCheck()
                saved = selection.settings
                edit = saved.configuration
                revision += 1
                sourceChanged(revision)
                startCheck(selectionError: selection.error)
                completion(true)
            } catch {
                storageError = error as? ReportStorageError ?? .writeFailed
                completion(false)
            }
        }
    }

    func cancelCheck() {
        checkRevision += 1
        checkTask?.cancel()
        checkTask = nil
        if isChecking {
            isChecking = false
            status = .unchecked
            error = .cancelled
            record(CodexCheckEvent(result: .cancelled, error: .cancelled, version: nil))
        }
    }

    private func startCheck(selectionError: CodexSourceError?) {
        error = selectionError
        status = .unchecked
        if let selectionError {
            status = .unavailable
            record(CodexCheckEvent(result: .failure, error: selectionError, version: nil))
            return
        }
        guard let identity = saved.identity else { return }
        let expected = checkRevision
        isChecking = true
        checkTask = Task {
            do {
                let version = try await access.check(identity)
                guard expected == checkRevision, !Task.isCancelled else { return }
                status = .available
                isChecking = false
                error = nil
                let checkedAt = now()
                record(CodexCheckEvent(result: .success, error: nil, version: version))
                do {
                    try await storage.saveCodexDiagnostic(identity: identity, checkedAt: checkedAt, version: version)
                    guard expected == checkRevision, !Task.isCancelled else { return }
                    saved.lastSuccessfulCheck = checkedAt
                    saved.version = version
                } catch {
                    guard expected == checkRevision, !Task.isCancelled else { return }
                    storageError = error as? ReportStorageError ?? .writeFailed
                }
            } catch {
                guard expected == checkRevision, !Task.isCancelled else { return }
                isChecking = false
                status = .unavailable
                let failure = error as? CodexSourceError ?? .transportInterrupted
                self.error = failure
                record(CodexCheckEvent(result: .failure, error: failure, version: nil))
            }
        }
    }
}
