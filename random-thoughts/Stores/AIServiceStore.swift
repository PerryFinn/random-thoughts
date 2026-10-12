import Foundation
import Observation

@MainActor
@Observable
final class AIServiceStore {
    private(set) var settings = AIServiceSettings()
    private(set) var edit = AIServiceEdit(configuration: AIServiceConfiguration(service: .chatCompletions))
    private(set) var editRevision: UInt64 = 0
    private(set) var storageError: ReportStorageError?
    private(set) var inputError: AIServiceInputError?
    private(set) var credentialError: AICredentialError?
    private(set) var notice: String?
    private(set) var credentialStatuses: [AIServiceType: AICredentialStatus] = [:]
    private(set) var revealedCredential: String?
    private(set) var isReadingCredential = false
    private var readRevision: UInt64 = 0
    @ObservationIgnored private var readTask: Task<Void, Never>?
    var selected: SavedAIService { settings.configurations[edit.configuration.service]! }
    var hasEdits: Bool { edit != AIServiceEdit(configuration: selected.configuration) }
    var credentialStatus: AICredentialStatus { credentialStatuses[edit.configuration.service] ?? .absent }
    var canMakeCurrent: Bool { !hasEdits && selected.hasMatchingValidation && credentialStatus == .readable }
    @ObservationIgnored private let storage: any DailyReportStorage
    @ObservationIgnored private let credentials: any AICredentialAccess
    @ObservationIgnored private let record: (AIServiceStorageEvent) -> Void

    init(storage: any DailyReportStorage, credentials: any AICredentialAccess, record: @escaping (AIServiceStorageEvent) -> Void) {
        self.storage = storage
        self.credentials = credentials
        self.record = record
    }
    func restore(_ settings: AIServiceSettings) async {
        self.settings = settings
        for service in AIServiceType.allCases {
            var saved = self.settings.configurations[service]!
            if saved.validation.baseline != saved.requestBaseline { saved.validation.invalidate() }
            self.settings.configurations[service] = saved
            credentialStatuses[service] = await status(of: saved.credential)
        }
        revert()
    }
    func setEdit(_ edit: AIServiceEdit) {
        hideCredential()
        self.edit = edit
        editRevision += 1
        notice = nil
    }
    func select(_ service: AIServiceType) {
        hideCredential()
        edit = AIServiceEdit(configuration: settings.configurations[service]!.configuration)
        editRevision += 1
        notice = nil
        inputError = nil
        credentialError = nil
    }
    func revert() { select(edit.configuration.service); storageError = nil; inputError = nil }
    func validateInput() -> AIServiceConfiguration? {
        do { let configuration = try edit.validatedConfiguration(); inputError = nil; return configuration }
        catch { inputError = error as? AIServiceInputError; return nil }
    }
    func save(configuration: AIServiceConfiguration, after previous: Task<Void, Never>?, completion: @escaping (Bool) -> Void) -> Task<Void, Never> {
        var saved = selected
        let oldBaseline = saved.requestBaseline
        saved.configuration = configuration
        let newCredential = edit.newCredential
        storageError = nil
        credentialError = nil
        hideCredential()
        return Task {
            await previous?.value
            do {
                if !newCredential.isEmpty {
                    saved.credential = try await credentials.seal(newCredential)
                    guard saved.credentialVersion < Int64.max else { throw ReportStorageError.invalidData }
                    saved.credentialVersion += 1
                }
                if saved.requestBaseline != oldBaseline { saved.validation.invalidate() }
                try await commit(saved)
                notice = "已保存 AI 服务配置"
                record(AIServiceStorageEvent(operation: .configuration, result: .success))
                completion(true)
            } catch {
                if let error = error as? AICredentialError { credentialError = error }
                else { storageError = error as? ReportStorageError ?? .writeFailed }
                record(AIServiceStorageEvent(operation: .configuration, result: .failure))
                completion(false)
            }
        }
    }

    func waitForCredential() async { await readTask?.value }
    func hideCredential() {
        readRevision += 1
        readTask?.cancel()
        revealedCredential = nil
        isReadingCredential = false
    }
    func readCredential(copy: Bool, copyText: @escaping (String) -> Void) {
        guard credentialStatus == .readable, let envelope = selected.credential else { return }
        hideCredential()
        let revision = readRevision
        let service = edit.configuration.service
        isReadingCredential = true
        readTask = Task {
            do {
                let value = try await credentials.open(envelope)
                guard !Task.isCancelled, revision == readRevision, service == edit.configuration.service,
                      selected.credential == envelope else { return }
                if copy { copyText(value); notice = "已复制凭据" }
                else { revealedCredential = value }
            } catch {
                guard !Task.isCancelled, revision == readRevision else { return }
                credentialError = error as? AICredentialError ?? .authenticationFailed
                credentialStatuses[service] = .unreadable(credentialError!)
            }
            if revision == readRevision { isReadingCredential = false }
        }
    }
    func canRequestDeletion() -> Bool {
        if hasEdits { notice = "请先保存或撤销配置编辑，再删除已保存凭据。"; return false }
        return selected.credential != nil
    }
    func deleteCredential(after previous: Task<Void, Never>?, completion: @escaping () -> Void) -> Task<Void, Never> {
        var saved = selected
        storageError = nil
        hideCredential()
        return Task {
            await previous?.value
            do {
                guard saved.credentialVersion < Int64.max else { throw ReportStorageError.invalidData }
                saved.credential = nil
                saved.credentialVersion += 1
                saved.validation.invalidate()
                try await commit(saved)
                notice = "已删除凭据，配置字段和当前身份保留"
                record(AIServiceStorageEvent(operation: .credentialDeletion, result: .success))
            } catch {
                storageError = error as? ReportStorageError ?? .writeFailed
                record(AIServiceStorageEvent(operation: .credentialDeletion, result: .failure))
            }
            completion()
        }
    }

    private func commit(_ saved: SavedAIService) async throws {
        try await storage.saveAIService(saved)
        settings.configurations[saved.configuration.service] = saved
        credentialStatuses[saved.configuration.service] = await status(of: saved.credential)
        revert()
    }

    func makeCurrent(after previous: Task<Void, Never>?, completion: @escaping () -> Void) -> Task<Void, Never> {
        let service = edit.configuration.service
        storageError = nil
        return Task {
            await previous?.value
            do {
                try await storage.saveCurrentAIService(service)
                settings.current = service
                notice = "已设为当前 AI 服务配置"
                record(AIServiceStorageEvent(operation: .currentSelection, result: .success))
            } catch {
                storageError = error as? ReportStorageError ?? .writeFailed
                record(AIServiceStorageEvent(operation: .currentSelection, result: .failure))
            }
            completion()
        }
    }

    func requestValidation() {
        if hasEdits { notice = "请先保存或撤销配置编辑，再校验已保存配置。"; return }
        if selected.configuration.endpoint.isEmpty { inputError = .missingEndpoint; return }
        if selected.configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { inputError = .missingModel; return }
        switch credentialStatus {
        case .absent: inputError = .missingCredential
        case .unreadable(let error): credentialError = error
        case .readable: notice = "协议校验尚未接入，配置仍未获得生成资格。"
        }
    }

    private func status(of envelope: AICredentialEnvelope?) async -> AICredentialStatus {
        guard let envelope else { return .absent }
        do { _ = try await credentials.open(envelope); return .readable }
        catch { return .unreadable(error as? AICredentialError ?? .authenticationFailed) }
    }
}
