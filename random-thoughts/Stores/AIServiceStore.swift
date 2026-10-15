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
    private(set) var isValidating = false
    private(set) var validationStage: AIProbeStage?
    private var validationRevision: UInt64 = 0
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    private var readRevision: UInt64 = 0
    @ObservationIgnored private var readTask: Task<Void, Never>?
    var selected: SavedAIService { settings.configurations[edit.configuration.service]! }
    var hasEdits: Bool { edit != AIServiceEdit(configuration: selected.configuration) }
    var credentialStatus: AICredentialStatus { credentialStatuses[edit.configuration.service] ?? .absent }
    var canMakeCurrent: Bool { !hasEdits && selected.hasMatchingValidation && credentialStatus == .readable }
    var currentGeneratable: SavedAIService? {
        guard let service = settings.current, let saved = settings.configurations[service],
              saved.hasMatchingValidation, credentialStatuses[service] == .readable else { return nil }
        return saved
    }
    func invalidate(_ baseline: AIValidationBaseline, after previous: Task<Void, Never>?) -> Task<Void, Never> {
        let proof: AIServiceValidation?
        if var saved = settings.configurations[baseline.service], saved.requestBaseline == baseline {
            saved.validation.status = .failed; saved.validation.streaming = .unknown; saved.validation.structured = .unknown
            settings.configurations[baseline.service] = saved
            proof = saved.validation
        } else { proof = nil }
        return Task {
            await previous?.value
            guard let proof, !Task.isCancelled,
                  settings.configurations[baseline.service]?.requestBaseline == baseline,
                  settings.configurations[baseline.service]?.validation == proof else { return }
            do { _ = try await storage.saveAIValidation(proof, matching: baseline) }
            catch { storageError = error as? ReportStorageError ?? .writeFailed }
        }
    }
    @ObservationIgnored private let storage: any DailyReportStorage
    @ObservationIgnored private let credentials: any AICredentialAccess
    @ObservationIgnored private let record: (AIServiceStorageEvent) -> Void
    @ObservationIgnored private let access: any AIServiceAccess
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let recordValidation: (AIValidationEvent) -> Void

    init(storage: any DailyReportStorage, credentials: any AICredentialAccess, access: any AIServiceAccess,
         now: @escaping () -> Date, record: @escaping (AIServiceStorageEvent) -> Void,
         recordValidation: @escaping (AIValidationEvent) -> Void) {
        self.storage = storage
        self.credentials = credentials
        self.record = record
        self.access = access
        self.now = now
        self.recordValidation = recordValidation
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
        let credentialStatus = await status(of: saved.credential)
        try await storage.saveAIService(saved)
        settings.configurations[saved.configuration.service] = saved
        credentialStatuses[saved.configuration.service] = credentialStatus
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
        case .readable: startValidation()
        }
    }

    func waitForValidation() async { await validationTask?.value }
    func cancelValidation() {
        guard isValidating else { return }
        recordValidation(.init(service: selected.configuration.service, stage: validationStage ?? .basic, result: .cancelled, capability: .unknown))
        validationRevision += 1
        validationTask?.cancel()
        isValidating = false
        validationStage = nil
        notice = AIRequestError.cancelled.message
    }

    private func startValidation() {
        guard !isValidating else { return }
        let saved = selected
        validationRevision += 1
        let revision = validationRevision
        isValidating = true
        notice = nil
        validationTask = Task {
            defer { if revision == validationRevision { isValidating = false; validationStage = nil } }
            do {
                let key = try await credentials.open(saved.credential!)
                var proof = AIServiceValidation(status: .validated, baseline: saved.requestBaseline, checkedAt: now())
                for stage in [AIProbeStage.basic, .streaming, .structured] {
                    guard !Task.isCancelled, revision == validationRevision else { return }
                    validationStage = stage
                    let schema = stage == .structured ? #"{"type":"object","properties":{"ok":{"type":"string"}},"required":["ok"],"additionalProperties":false}"# : nil
                    do {
                        let text = try await access.execute(AIRequest(intent: .probe(stage), configuration: saved.configuration,
                            credential: key, instruction: "Only synthetic configuration testing. Return OK, or {\"ok\":\"OK\"} for the JSON schema.",
                            input: "Synthetic probe. No work content.", schema: schema, streaming: stage == .streaming))
                        if stage == .structured {
                            guard let value = try? StrictStringObject.parse(text),
                                  value.count == 1, value["ok"] == "OK" else { throw AIRequestError.invalidResponse }
                        }
                        if stage == .streaming { proof.streaming = .supported }
                        if stage == .structured { proof.structured = .supported }
                        recordValidation(.init(service: saved.configuration.service, stage: stage, result: .success, capability: .supported))
                    } catch {
                        let rawFailure = AIRequestError.reason(for: error)
                        let optionalRejection = (stage == .streaming && rawFailure == .streamingUnsupported)
                            || (stage == .structured && rawFailure == .structuredUnsupported)
                        let failure = !optionalRejection && [.streamingUnsupported, .structuredUnsupported].contains(rawFailure) ? .parameters : rawFailure
                        guard !Task.isCancelled, revision == validationRevision else { return }
                        recordValidation(.init(service: saved.configuration.service, stage: stage,
                                               result: failure.invalidatesConfiguration ? .failure : .unfinished,
                                               capability: [.streamingUnsupported, .structuredUnsupported].contains(failure) ? .unsupported : .unknown))
                        if stage == .streaming, failure == .streamingUnsupported { proof.streaming = .unsupported; continue }
                        if stage == .structured, failure == .structuredUnsupported { proof.structured = .unsupported; continue }
                        if failure.invalidatesConfiguration {
                            proof.status = .failed; proof.streaming = .unknown; proof.structured = .unknown
                            try await saveProof(proof, saved: saved, revision: revision)
                            notice = failure.message
                            return
                        }
                        notice = "配置校验未完成，原校验结论保留。"
                        return
                    }
                }
                try await saveProof(proof, saved: saved, revision: revision)
                if revision == validationRevision { notice = "配置校验完成；请另行设为当前。" }
            } catch {
                guard !Task.isCancelled, revision == validationRevision else { return }
                storageError = error as? ReportStorageError
                notice = "配置校验未完成，原校验结论保留。"
            }
        }
    }

    private func saveProof(_ proof: AIServiceValidation, saved: SavedAIService, revision: UInt64) async throws {
        guard !Task.isCancelled, revision == validationRevision,
              settings.configurations[saved.configuration.service]?.requestBaseline == saved.requestBaseline else { return }
        var updated = settings.configurations[saved.configuration.service]!
        updated.validation = proof
        guard try await storage.saveAIValidation(proof, matching: saved.requestBaseline) else { return }
        guard !Task.isCancelled, revision == validationRevision,
              settings.configurations[saved.configuration.service]?.requestBaseline == saved.requestBaseline else { return }
        settings.configurations[saved.configuration.service] = updated
    }

    private func status(of envelope: AICredentialEnvelope?) async -> AICredentialStatus {
        guard let envelope else { return .absent }
        do { _ = try await credentials.open(envelope); return .readable }
        catch { return .unreadable(error as? AICredentialError ?? .authenticationFailed) }
    }
}
