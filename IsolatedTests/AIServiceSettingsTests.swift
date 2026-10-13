import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct AIServiceSettingsTests {
    @Test(arguments: ["leave", "save"])
    func unicodeEquivalentModelIdentifiersRemainDistinctEditsAndRequireNewValidation(_ action: String) async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .responses))
        saved.configuration.endpoint = "https://example.invalid/exact-model/"
        saved.configuration.model = "caf\u{00e9}"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_UNICODE_KEY_27")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline,
                                              checkedAt: environment.now, streaming: .supported, structured: .supported)
        var settings = AIServiceSettings(); settings.configurations[.responses] = saved; settings.current = .responses
        await environment.storage.setAISettings(settings)
        let flow = try await prepareAISettings(environment)
        flow.send(.selectAIServiceType(.responses))
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit; edit.configuration.model = "cafe\u{0301}"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        #expect(flow.hasAIServiceEdits)
        if action == "leave" {
            flow.send(.selectAIServiceType(.messages))
            #expect(flow.confirmation != nil)
            #expect(flow.aiServiceEdit.configuration.service == .responses)
            #expect(flow.aiServiceEdit.configuration.model.utf8.elementsEqual("cafe\u{0301}".utf8))
        } else {
            flow.send(.saveAIService); await flow.waitForStorage()
            #expect(flow.savedAIService.configuration.model.utf8.elementsEqual("cafe\u{0301}".utf8))
            #expect(flow.savedAIService.validation.status == .needsRevalidation)
            #expect(flow.savedAIService.validation.streaming == .unknown)
            #expect(!flow.canMakeAIServiceCurrent)
            #expect(flow.currentAIService == .responses)
            #expect(flow.savedAIService.credential == saved.credential)
        }
    }

    @Test(arguments: ["confirmation", "editor"])
    func leavingTheAIPageInvalidatesDeletionAndEditorCallbacksEvenAfterReturning(_ callback: String) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit; edit.newCredential = "SYNTHETIC_PAGE_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        let saved = flow.savedAIService
        let revision = flow.aiServiceEditRevision
        var lateEdit = flow.aiServiceEdit; lateEdit.newCredential = "SYNTHETIC_LATE_PAGE_KEY_27"
        flow.send(.requestDeleteAICredential)
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.requestSettingsPage(.general))
        #expect(flow.confirmation == nil)
        flow.send(.requestSettingsPage(.aiServices))
        if callback == "confirmation" { flow.send(.confirm(obsolete)); await flow.waitForStorage() }
        else { flow.send(.editAIService(lateEdit, session: session, revision: revision)) }
        #expect(flow.savedAIService == saved)
        #expect(!flow.hasAIServiceEdits)
        #expect(flow.aiServiceEdit.newCredential.isEmpty)
    }

    @Test(arguments: ["type", "page", "close", "quit"])
    func leavingProtectsOneEditorAndRejectsExpiredConfirmationsAndFailedSaves(_ target: String) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        flow.send(.open(.report))
        flow.send(.editBody("保留的日报草稿", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        var edit = flow.aiServiceEdit
        edit.configuration.model = "synthetic-unsaved"
        edit.newCredential = "SYNTHETIC_UNSAVED_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        func leave() {
            switch target {
            case "type": flow.send(.selectAIServiceType(.responses))
            case "page": flow.send(.requestSettingsPage(.general))
            case "close": flow.send(.requestCloseSettings(session))
            default: flow.send(.quit)
            }
        }
        leave()
        let obsolete = try #require(flow.confirmation)
        #expect(obsolete.windowKind == .settings)
        #expect(flow.settingsPage == .aiServices)
        #expect(flow.aiServiceEdit.configuration.service == .chatCompletions)
        #expect(!flow.canTerminate)
        if target == "quit" { #expect(obsolete.draftDays == flow.draftDays) }
        flow.send(.cancelConfirmation)
        #expect(flow.aiServiceEdit == edit)
        leave()
        edit.configuration.model = "synthetic-updated"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        let refreshed = try #require(flow.confirmation)
        flow.send(.confirm(obsolete.id))
        #expect(flow.confirmation?.id == refreshed.id)
        await environment.storage.failSaves(true)
        flow.send(.confirm(refreshed.id))
        await flow.waitForStorage()
        #expect(flow.aiServiceEdit == edit)
        #expect(flow.settingsPage == .aiServices)
        #expect(flow.aiServiceStorageError == .writeFailed)
        #expect(flow.hasDraft)
        await environment.storage.failSaves(false)
        leave()
        flow.send(.confirm(try #require(flow.confirmation?.id)))
        await flow.waitForStorage()
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.configuration.model == "synthetic-updated")
        #expect(!flow.hasAIServiceEdits)
        switch target {
        case "type": #expect(flow.aiServiceEdit.configuration.service == .responses)
        case "page": #expect(flow.settingsPage == .general)
        case "close": #expect(environment.effects.contains(.closeSettings(session: session)))
        default: #expect(environment.effects.contains(.quit)); #expect(!flow.hasDraft)
        }
    }

    @Test func discardingProtocolEditsReleasesThemAndOldWindowAndEditorCallbacksCannotRestoreThem() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        let revision = flow.aiServiceEditRevision
        var old = flow.aiServiceEdit; old.newCredential = "SYNTHETIC_OLD_EDITOR_27"
        flow.send(.editAIService(old, session: session, revision: revision))
        flow.send(.selectAIServiceType(.messages))
        flow.send(.discardSettingsAndContinue(try #require(flow.confirmation?.id)))
        #expect(flow.aiServiceEdit.configuration.service == .messages)
        #expect(flow.aiServiceEdit.newCredential.isEmpty)
        flow.send(.editAIService(old, session: session, revision: revision))
        #expect(!flow.hasAIServiceEdits)
        flow.send(.windowClosed(.settings, session: session))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices))
        var edit = flow.aiServiceEdit; edit.newCredential = "SYNTHETIC_LATE_WINDOW_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        #expect(!flow.hasAIServiceEdits)
    }

    @Test func credentialDisplayAndCopyAreExplicitAndLateReadsCannotCrossProtocolOrWindowBoundaries() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit; edit.newCredential = "SYNTHETIC_COPY_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.revealedAICredential == nil)
        #expect(environment.copies.isEmpty)
        flow.send(.showAICredential); await flow.waitForAICredential()
        #expect(flow.revealedAICredential == "SYNTHETIC_COPY_KEY_27")
        #expect(environment.copies.isEmpty)
        flow.send(.hideAICredential)
        flow.send(.copyAICredential); await flow.waitForAICredential()
        #expect(environment.copies == ["SYNTHETIC_COPY_KEY_27"])
        #expect(flow.revealedAICredential == nil)
        await environment.credentials.holdNextOpen()
        flow.send(.showAICredential)
        await environment.credentials.waitUntilOpenIsHeld()
        flow.send(.selectAIServiceType(.messages))
        await environment.credentials.releaseOpen()
        await flow.waitForAICredential()
        #expect(flow.revealedAICredential == nil)
        flow.send(.selectAIServiceType(.chatCompletions))
        await environment.credentials.holdNextOpen()
        flow.send(.copyAICredential)
        await environment.credentials.waitUntilOpenIsHeld()
        flow.send(.windowClosed(.settings, session: session))
        await environment.credentials.releaseOpen()
        await flow.waitForAICredential()
        #expect(environment.copies == ["SYNTHETIC_COPY_KEY_27"])
        #expect(flow.revealedAICredential == nil)
    }

    @Test func credentialDeletionRequiresCleanEditsAndFreshConfirmationAndKeepsFieldsAndCurrentOnFailure() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/delete/"
        saved.configuration.model = "synthetic-delete"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_DELETE_KEY_27")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline, checkedAt: environment.now)
        var settings = AIServiceSettings(); settings.configurations[.chatCompletions] = saved; settings.current = .chatCompletions
        await environment.storage.setAISettings(settings)
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit; edit.configuration.model = "unsaved"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.requestDeleteAICredential)
        #expect(flow.confirmation == nil)
        #expect(flow.aiServiceNotice == "请先保存或撤销配置编辑，再删除已保存凭据。")
        flow.send(.revertAIService)
        flow.send(.requestDeleteAICredential)
        let obsolete = try #require(flow.confirmation?.id)
        flow.send(.cancelConfirmation)
        #expect(flow.savedAIService == saved)
        flow.send(.requestDeleteAICredential)
        let current = try #require(flow.confirmation?.id)
        flow.send(.confirm(obsolete))
        #expect(flow.confirmation?.id == current)
        await environment.storage.failSaves(true)
        flow.send(.confirm(current)); await flow.waitForStorage()
        #expect(flow.savedAIService == saved)
        #expect(flow.currentAIService == .chatCompletions)
        await environment.storage.failSaves(false)
        flow.send(.requestDeleteAICredential)
        flow.send(.confirm(try #require(flow.confirmation?.id))); await flow.waitForStorage()
        #expect(flow.savedAIService.credential == nil)
        #expect(flow.savedAIService.credentialVersion == 2)
        #expect(flow.savedAIService.configuration == saved.configuration)
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        #expect(flow.currentAIService == .chatCompletions)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == flow.savedAIService)
    }

    @Test func exactRequestBaselinesKeepCurrentIdentityAndExcludeBudgetAndConcurrency() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .responses))
        saved.configuration.endpoint = "https://example.invalid/route/?x=1"
        saved.configuration.model = "synthetic-model"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_BASELINE_KEY_27")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline,
                                              checkedAt: environment.now, streaming: .supported, structured: .unsupported)
        var settings = AIServiceSettings()
        settings.configurations[.responses] = saved
        await environment.storage.setAISettings(settings)
        let flow = try await prepareAISettings(environment)
        flow.send(.selectAIServiceType(.responses))
        #expect(flow.canMakeAIServiceCurrent)
        #expect(flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent)
        await flow.waitForStorage()
        #expect(flow.currentAIService == .responses)
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit
        edit.totalBudget = "100000"; edit.concurrency = "1"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(flow.savedAIService.validation == saved.validation)
        #expect(flow.canMakeAIServiceCurrent)
        edit = flow.aiServiceEdit; edit.outputLimit = "12000"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        #expect(flow.savedAIService.validation.streaming == .unknown)
        #expect(!flow.canMakeAIServiceCurrent)
        #expect(flow.currentAIService == .responses)
        #expect(try await environment.storage.load().aiServices.current == .responses)
        #expect(saved.requestBaseline.store == false)
        #expect(saved.requestBaseline.truncation == .disabled)
        #expect(saved.requestBaseline.authentication == .bearer)
        for service in AIServiceType.allCases {
            let baseline = SavedAIService(configuration: AIServiceConfiguration(service: service)).requestBaseline
            #expect(baseline.probeContractVersion == 1)
            if service == .messages {
                #expect(baseline.store == nil && baseline.truncation == nil)
                #expect(baseline.authentication == .messages(version: "2023-06-01"))
            } else if service == .chatCompletions { #expect(baseline.store == false && baseline.truncation == nil) }
        }
    }

    @Test(arguments: ["endpoint", "model", "defaults", "credential"])
    func requestChangesInvalidateTheProofWithoutAutomaticallyChangingCurrent(_ change: String) async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .chatCompletions))
        saved.configuration.endpoint = "https://example.invalid/path/?query=original"
        saved.configuration.model = "synthetic-original"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_REQUEST_KEY_27")
        saved.credentialVersion = 1
        saved.validation = AIServiceValidation(status: .validated, baseline: saved.requestBaseline,
                                              checkedAt: environment.now, streaming: .supported, structured: .supported)
        var settings = AIServiceSettings(); settings.configurations[.chatCompletions] = saved; settings.current = .chatCompletions
        await environment.storage.setAISettings(settings)
        let flow = try await prepareAISettings(environment)
        var edit = flow.aiServiceEdit
        switch change {
        case "endpoint": edit.configuration.endpoint += "&extra=1"
        case "model": edit.configuration.model = "synthetic-new"
        case "defaults": edit.configuration.defaults = .chatCompletions(ChatCompletionsDefaults(reasoningEffort: .high))
        default: edit.newCredential = "SYNTHETIC_REQUEST_KEY_27"
        }
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        #expect(flow.currentAIService == .chatCompletions)
        #expect(!flow.canMakeAIServiceCurrent)
        #expect(flow.savedAIService.requestBaseline != saved.requestBaseline)
    }

    @Test func incompleteUnvalidatedAndRestoredMismatchedProofsCannotBecomeCurrent() async throws {
        let environment = ReportFlowTestEnvironment()
        var saved = SavedAIService(configuration: AIServiceConfiguration(service: .messages))
        saved.configuration.endpoint = "https://example.invalid/messages"
        saved.configuration.model = "synthetic-model"
        saved.credential = try await environment.credentials.seal("SYNTHETIC_RESTORE_KEY_27")
        saved.credentialVersion = 1
        let obsolete = saved.requestBaseline
        saved.configuration.outputLimit = 10000
        saved.validation = AIServiceValidation(status: .validated, baseline: obsolete, checkedAt: environment.now,
                                              streaming: .supported, structured: .supported)
        var settings = AIServiceSettings(); settings.configurations[.messages] = saved; settings.current = .messages
        await environment.storage.setAISettings(settings)
        let flow = try await prepareAISettings(environment)
        flow.send(.makeAIServiceCurrent)
        #expect(flow.currentAIService == .messages)
        flow.send(.selectAIServiceType(.messages))
        #expect(flow.savedAIService.validation.status == .needsRevalidation)
        #expect(flow.savedAIService.validation.streaming == .unknown)
        #expect(!flow.canMakeAIServiceCurrent)
        flow.send(.requestAIValidation)
        #expect(flow.aiServiceNotice == AIRequestError.unsupportedService.message)
        #expect(await environment.codex.checkCount == 0)
    }

    @Test func replacingCredentialsCommitsAllFieldsTogetherAndFailureKeepsOldValuesAndNewInput() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = "https://example.invalid/first/"
        edit.newCredential = "SYNTHETIC_FIRST_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        let old = try #require(try await environment.storage.load().aiServices.configurations[.chatCompletions])
        #expect(old.credentialVersion == 1)
        #expect(try await environment.credentials.open(try #require(old.credential)) == "SYNTHETIC_FIRST_KEY_27")
        #expect(flow.aiServiceEdit.newCredential.isEmpty)
        edit = flow.aiServiceEdit
        edit.configuration.endpoint = "https://example.invalid/replacement?x=2"
        edit.newCredential = "SYNTHETIC_REPLACED_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        await environment.credentials.failEncryption(true)
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == old)
        #expect(flow.aiServiceEdit == edit)
        #expect(flow.aiCredentialError == .encryptionFailed)
        await environment.credentials.failEncryption(false)
        await environment.storage.failSaves(true)
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions] == old)
        #expect(flow.aiServiceEdit == edit)
        #expect(flow.aiServiceStorageError == .writeFailed)
        await environment.storage.failSaves(false)
        flow.send(.saveAIService)
        await flow.waitForStorage()
        let replacement = try #require(try await environment.storage.load().aiServices.configurations[.chatCompletions])
        #expect(replacement.credentialVersion == 2)
        #expect(replacement.configuration.endpoint == edit.configuration.endpoint)
        #expect(try await environment.credentials.open(try #require(replacement.credential)) == edit.newCredential)
        let preserved = replacement.credential
        edit = flow.aiServiceEdit
        edit.configuration.model = "synthetic-model"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.credential == preserved)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.credentialVersion == 2)
    }

    @Test(arguments: [
        "https:///no-host", "https://user@example.invalid/", "https://user:pass@example.invalid/",
        "https://example.invalid/#fragment", "ftp://example.invalid/path", "/relative", "https://example.invalid/a b", "https://example.invalid/%QZ"
    ])
    func invalidEndpointsKeepTheSavedConfigurationAndFocusableError(_ endpoint: String) async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = endpoint
        flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService)
        await flow.waitForStorage()
        #expect(flow.aiServiceInputError == .invalidEndpoint)
        #expect(flow.aiServiceEdit == edit)
        #expect(try await environment.storage.load().aiServices.configurations[.chatCompletions]?.configuration.endpoint == "")
    }

    @Test func nativeDefaultsAndBudgetsPreserveUnsetZeroAndNoneAndRejectInvalidRanges() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        for service in AIServiceType.allCases {
            flow.send(.selectAIServiceType(service))
            var edit = flow.aiServiceEdit
            edit.configuration.endpoint = "http://localhost:8080/custom/?query=a%2Fb"
            edit.temperature = "0"
            edit.totalBudget = "30000"; edit.outputLimit = "12000"; edit.concurrency = "8"
            switch service {
            case .chatCompletions: edit.configuration.defaults = .chatCompletions(ChatCompletionsDefaults(reasoningEffort: AIReasoningEffort.none))
            case .responses: edit.configuration.defaults = .responses(ResponsesDefaults(reasoningEffort: AIReasoningEffort.none))
            case .messages: edit.configuration.defaults = .messages(MessagesDefaults(thinking: .adaptive, effort: .max))
            }
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
            await flow.waitForStorage()
            let saved = try #require(try await environment.storage.load().aiServices.configurations[service])
            #expect(saved.configuration.defaults.temperature == 0)
            #expect(saved.configuration.totalBudget == 30000)
            #expect(saved.configuration.outputLimit == 12000)
            #expect(saved.configuration.concurrency == 8)
            #expect(flow.aiServiceUsesPlainHTTP)
            var invalid = flow.aiServiceEdit
            invalid.temperature = service == .messages ? "1.1" : "2.1"
            flow.send(.editAIService(invalid, session: session, revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
            #expect(flow.aiServiceInputError == .invalidTemperature)
            invalid.temperature = "NaN"
            flow.send(.editAIService(invalid, session: session, revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
            #expect(flow.aiServiceInputError == .invalidTemperature)
            flow.send(.revertAIService)
        }
        for (budget, output, concurrency, expected) in [
            ("", "1", "3", AIServiceInputError.invalidTotalBudget), ("1", "1", "3", .invalidOutputLimit),
            ("0", "1", "3", .invalidTotalBudget), ("2", "0", "3", .invalidOutputLimit),
            ("2", "1.5", "3", .invalidOutputLimit), ("2", "1", "9", .invalidConcurrency),
            ("2", "1", "0", .invalidConcurrency), ("99999999999999999999999", "1", "3", .invalidTotalBudget)
        ] {
            var edit = flow.aiServiceEdit
            edit.totalBudget = budget; edit.outputLimit = output; edit.concurrency = concurrency
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
            #expect(flow.aiServiceInputError == expected)
            #expect(flow.aiServiceEdit == edit)
        }
        flow.send(.revertAIService)
        #expect(try await environment.storage.load().aiServices.configurations[.messages]?.configuration.defaults == .messages(MessagesDefaults(temperature: 0, thinking: .adaptive, effort: .max)))
    }

    @Test func savingIncompleteServicesKeepsThreeIsolatedConfigurationsWithoutSelectingOrRequesting() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices))
        let session = try #require(flow.openWindows[.settings])
        #expect(flow.aiServiceEdit.configuration.endpoint.isEmpty)
        #expect(flow.aiServiceEdit.totalBudget == "65536")
        #expect(flow.aiServiceEdit.outputLimit == "16384")
        #expect(flow.aiServiceEdit.concurrency == "3")
        for service in AIServiceType.allCases {
            flow.send(.selectAIServiceType(service))
            var edit = flow.aiServiceEdit
            edit.configuration.endpoint = "  https://example.invalid:8443/Custom/route/?tenant=a%2Fb&v=1  \n"
            edit.configuration.model = "synthetic-\(service.rawValue)"
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService)
            await flow.waitForStorage()
            #expect(flow.aiServiceEdit.configuration.endpoint == "https://example.invalid:8443/Custom/route/?tenant=a%2Fb&v=1")
            #expect(!flow.hasAIServiceEdits)
        }
        let saved = try await environment.storage.load().aiServices
        #expect(saved.configurations.count == 3)
        #expect(saved.current == nil)
        #expect(flow.currentAIService == nil)
        for service in AIServiceType.allCases {
            #expect(saved.configurations[service]?.configuration.model == "synthetic-\(service.rawValue)")
            #expect(saved.configurations[service]?.validation.status == .unvalidated)
            #expect(saved.configurations[service]?.credential == nil)
        }
        #expect(await environment.codex.checkCount == 0)
        #expect(await environment.codex.scanCount == 0)
    }
}

@MainActor
func prepareAISettings(_ environment: ReportFlowTestEnvironment) async throws -> DailyReportFlow {
    let flow = environment.makeFlow()
    flow.send(.open(.settings))
    await flow.waitForStorage()
    flow.send(.requestSettingsPage(.aiServices))
    return flow
}
