import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct AIServicePrivacyTests {
    @Test func realEncryptionAndStorageThroughTheFlowExposeCredentialsOnlyOnExplicitCopyAndKeepLogObjectsClean() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let credentials = ControlledCredentials()
        let codex = ControlledCodexSource()
        let log = DDLog()
        let memory = MemoryWindowLogger()
        log.add(memory)
        let telemetry = DailyReportTelemetry(log: log)
        var copies: [String] = []
        let flow = DailyReportFlow(storage: database, aiCredentials: credentials, codexSourceAccess: codex,
                                   now: { environment.clock.now }, timeZone: .gmt,
                                   performWindowEffect: { _ in }, performContextEffect: { _ in }, recordWindowMode: { _ in },
                                   recordCodexCheck: { _ in }, recordSessionScan: { _ in },
                                   recordAIStorage: { telemetry.storageFinished($0) },
                                   redactCredentials: { $0 }, copyText: { copies.append($0) })
        flow.send(.open(.settings)); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices))
        let session = try #require(flow.openWindows[.settings])
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = "https://ENDPOINT_SECRET_27.invalid/Route?query=QUERY_SECRET_27"
        edit.configuration.model = "MODEL_SECRET_27"
        edit.newCredential = "SYNTHETIC_LOG_OLD_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        let original = flow.savedAIService
        edit = flow.aiServiceEdit
        edit.newCredential = "SYNTHETIC_LOG_NEW_KEY_27"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        await credentials.failEncryption(true)
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(flow.savedAIService == original)
        #expect(flow.aiServiceEdit.newCredential == edit.newCredential)
        await credentials.failEncryption(false)
        flow.send(.saveAIService); await flow.waitForStorage()
        let envelope = try #require(flow.savedAIService.credential)
        #expect(flow.aiServiceEdit.newCredential.isEmpty)
        #expect(copies.isEmpty && flow.revealedAICredential == nil)
        flow.send(.copyAICredential); await flow.waitForAICredential()
        #expect(copies == ["SYNTHETIC_LOG_NEW_KEY_27"])
        #expect(flow.revealedAICredential == nil)
        flow.send(.requestDeleteAICredential)
        flow.send(.cancelConfirmation)
        #expect(flow.savedAIService.credential == envelope)
        flow.send(.requestDeleteAICredential)
        flow.send(.confirm(try #require(flow.confirmation?.id))); await flow.waitForStorage()
        #expect(flow.savedAIService.credential == nil)
        #expect(await codex.checkCount == 0)
        #expect(await codex.scanCount == 0)
        for file in try FileManager.default.contentsOfDirectory(at: environment.directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            #expect(bytes.range(of: Data("SYNTHETIC_LOG_".utf8)) == nil)
        }
        #expect(!String(describing: environment.defaults.dictionaryRepresentation()).contains("SYNTHETIC_LOG_"))
        log.flushLog()
        let messages = memory.snapshot()
        #expect(messages.map(\.message) == [
            "report_storage_finished operation=configuration result=success schema=4 credential_format=1",
            "report_storage_finished operation=configuration result=failure schema=4 credential_format=1",
            "report_storage_finished operation=configuration result=success schema=4 credential_format=1",
            "report_storage_finished operation=credentialDeletion result=success schema=4 credential_format=1"
        ])
        let forbidden = ["SYNTHETIC_LOG_", "ENDPOINT_SECRET_27", "QUERY_SECRET_27", "MODEL_SECRET_27",
                         envelope.combined.base64EncodedString(), environment.credentialKey.base64EncodedString()]
        for message in messages {
            #expect(forbidden.allSatisfy { !message.message.contains($0) && !message.messageFormat.contains($0) })
            #expect(message.file == "DailyReports" && message.function == "report_storage_finished")
            #expect(message.line == 0 && message.context == 0 && message.representedObject == nil)
        }
        #expect(memory.logFormatter == nil)
        await database.close()
    }
}
