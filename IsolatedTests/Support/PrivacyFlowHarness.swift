import CocoaLumberjack
import Foundation
import Testing
@testable import random_thoughts

// Uses the agreed action/state seam with real storage, encryption, tokenizer,
// protocol adapters and logging. Only external processes, HTTP and clipboard are synthetic.
@MainActor
final class PrivacyFlowHarness {
    let environment: IsolatedTestEnvironment
    let storageDirectory: URL
    var databaseURL: URL { storageDirectory.appendingPathComponent("reports.sqlite") }
    let database: DailyReportDatabase
    let credentials: AIServiceCredentialCipher
    let codex: CodexDataSourceReader
    let transport: SyntheticTransport
    let access: PrivacyProtocolService
    let log = DDLog()
    let memory = MemoryWindowLogger()
    let key = "DEDICATED_KEY_PRIVATE_34"
    let highConfidenceKey = "ghp_SYNTHETIC34abcdefghijklmnopqrstuvwxyz"
    let ordinaryText = "王小明 alice@example.invalid 星河项目 /ordinary/BODY_PATH_PRIVATE_34"
    var copies: [String] = []
    private(set) var flow: DailyReportFlow!

    init(streaming: Bool, redactionFails: Bool = false) throws {
        environment = try IsolatedTestEnvironment()
        storageDirectory = environment.directory.appendingPathComponent("storage")
        database = DailyReportDatabase(directory: storageDirectory)
        credentials = AIServiceCredentialCipher(key: environment.credentialKey)
        codex = try scanReader(environment, fixture: ["scenario": "empty"])
        transport = SyntheticTransport(endpoint: URL(string: "https://\(UUID().uuidString).fixture.invalid/ENDPOINT_PRIVATE_34/?query=QUERY_PRIVATE_34%2Fprobe")!)
        access = PrivacyProtocolService(transport: transport, streamingSupported: streaming)
        log.add(memory)
        let telemetry = DailyReportTelemetry(log: log), clock = environment.clock
        flow = DailyReportFlow(storage: database, aiCredentials: credentials, aiAccess: access,
            reportTokenizer: OfflineReportTokenizer(), codexSourceAccess: codex, now: { clock.now }, timeZone: .gmt,
            performWindowEffect: { _ in }, performContextEffect: { _ in },
            recordWindowMode: { telemetry.windowModeChanged($0) }, recordCodexCheck: { telemetry.codexCheckFinished($0) },
            recordSessionScan: { telemetry.sessionScanFinished($0) }, recordAIStorage: { telemetry.storageFinished($0) },
            recordAIValidation: { telemetry.validationFinished($0) }, recordGeneration: { telemetry.generationChanged($0) },
            redactCredentials: { text in
                if redactionFails { throw RedactionFailure.synthetic }
                return try CredentialRedaction.redact(text)
            }, copyText: { [weak self] in self?.copies.append($0) })
    }

    func prepare(_ service: AIServiceType, batched: Bool) async throws {
        flow.send(.open(.settings)); flow.send(.open(.report)); await flow.waitForStorage()
        let session = try #require(flow.openWindows[.settings])
        flow.send(.requestSettingsPage(.general))
        var general = flow.generalSettingsEdit
        general.generationPreferences = "PREFERENCES_PRIVATE_34"
        flow.send(.editGeneralSettings(general, session: session)); flow.send(.saveGeneralSettings)
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(service))
        var edit = flow.aiServiceEdit
        edit.configuration.endpoint = transport.endpoint.absoluteString
        edit.configuration.model = "MODEL_PRIVATE_34"; edit.newCredential = key
        edit.totalBudget = "12000"; edit.outputLimit = "3000"; edit.concurrency = "1"
        flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
        flow.send(.saveAIService); await flow.waitForStorage()
        #expect(transport.requests.isEmpty && flow.currentAIService == nil)
        flow.send(.requestAIValidation); await flow.waitForAIValidation()
        #expect(flow.savedAIService.hasMatchingValidation && flow.currentAIService == nil)
        flow.send(.makeAIServiceCurrent); await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        let source = try scanIdentity(environment)
        flow.send(.editCodexSource(.init(mode: .manual, executablePath: source.executablePath,
            explicitDirectory: source.dataDirectory), session: session))
        flow.send(.saveCodexSource)
        await flow.waitForStorage(); await flow.waitForCodexCheck()
        #expect(flow.codexSourceStatus == .available)
        let day = flow.selectedDay
        let candidate = CodexCandidateSession(id: "SOURCE_ID_PRIVATE_34", title: "SOURCE_TITLE_PRIVATE_34",
            workDirectory: "/SOURCE_DIRECTORY_PRIVATE_34", origin: .user,
            turns: [.init(id: "TURN_ID_PRIVATE_34", startedAt: environment.clock.now, day: day,
                userText: "RAW_WORK_PRIVATE_34 \(ordinaryText) \(key) \(highConfidenceKey)"
                    + (batched ? String(repeating: " evidence", count: 40_000) : ""), finalAnswer: nil)], background: [])
        try install(candidate)
        flow.send(.scanSessions); await flow.waitForSessionScan()
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        #expect(flow.confirmedSnapshot?.sessions.first?.id == candidate.id)
    }

    func install(_ candidate: CodexCandidateSession) throws {
        let turns = candidate.turns.map { turn in
            syntheticTurn(id: turn.id, at: turn.day.start.timeIntervalSince1970 + 1_000,
                user: turn.userText, final: turn.finalAnswer)
        }
        let thread = syntheticSession(id: candidate.id, name: candidate.title,
            cwd: candidate.workDirectory ?? "/synthetic", turns: turns)
        try JSONSerialization.data(withJSONObject: ["scenario": "scan", "currentPages": [[thread]], "archivedPages": [[]],
            "threads": [candidate.id: thread]]).write(to: environment.directory.appendingPathComponent("fixture.json"))
    }

    var launches: Int {
        get throws { try #require(Int(String(contentsOf: environment.directory.appendingPathComponent("launches"), encoding: .utf8))) }
    }

    func generate() async throws {
        flow.send(.generateReport); await flow.waitForGeneration()
        if let confirmation = flow.confirmation {
            flow.send(.confirm(confirmation.id)); await flow.waitForGeneration()
        }
    }

    func edit(_ markdown: String) throws {
        flow.send(.editBody(markdown, day: flow.selectedDay, session: try #require(flow.openWindows[.report]),
            revision: flow.reportEditRevision))
    }

    func expectNoCopies(onDisk forbidden: [String]) throws {
        for file in try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: file)
            #expect(forbidden.allSatisfy { data.range(of: Data($0.utf8)) == nil && !file.lastPathComponent.contains($0) })
        }
        // standard is also confined to CFFIXED_USER_HOME by the runner's sandbox.
        let preferences = String(describing: environment.defaults.dictionaryRepresentation())
            + String(describing: UserDefaults.standard.dictionaryRepresentation())
        let forbiddenPreferences = forbidden + ["PREFERENCES_PRIVATE_34", "MODEL_PRIVATE_34", "ENDPOINT_PRIVATE_34", "QUERY_PRIVATE_34"]
        #expect(forbiddenPreferences.allSatisfy { !preferences.contains($0) })
    }

    private enum RedactionFailure: Error { case synthetic }
}
