import CocoaLumberjack
import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportPrivacyIntegrationTests {
    @Test(arguments: AIServiceType.allCases, [false, true])
    func nativeProtocolsShareOnlyAllowedContentAcrossWindowsDatesAndStorage(_ service: AIServiceType, _ batched: Bool) async throws {
        let h = try PrivacyFlowHarness(streaming: batched)
        defer { h.transport.close(); h.environment.close() }
        try await h.prepare(service, batched: batched)
        let flow = h.flow!, today = flow.selectedDay
        let snapshot = try #require(flow.confirmedSnapshot)
        #expect(snapshot.sessions[0].turns[0].userText.contains(h.key))
        #expect(!snapshot.sessions[0].turns[0].userText.contains(h.highConfidenceKey))
        let historyDay = ReportDay(date: today.start.addingTimeInterval(-1), timeZone: .gmt)
        // Explicit user text may contain a secret at rest; its outbound copy must be masked.
        flow.send(.selectReportDay(historyDay))
        let history = "HISTORY_SAVED_PRIVATE_34 \(h.highConfidenceKey)"
        try h.edit(history); flow.send(.copyMarkdown)
        flow.send(.save); await flow.waitForStorage()
        #expect(flow.body == history && h.copies == [history])
        flow.send(.moveDate(-1)); try h.edit("UNSAVED_DRAFT_PRIVATE_34")
        flow.send(.selectReportDay(today))
        let settingsSession = try #require(flow.openWindows[.settings])
        flow.send(.windowClosed(.settings, session: settingsSession)); flow.send(.open(.settings))
        #expect(flow.confirmedSnapshot == snapshot)
        try await h.generate()
        #expect(flow.hasDraft && flow.generationSources != nil && flow.generationError == nil)
        #expect(flow.body.contains("RESULT_PRIVATE_34") && !flow.body.contains(h.key))
        #expect(!flow.body.contains("INTERMEDIATE_PRIVATE_34"))
        #expect(flow.confirmedSnapshot == snapshot)
        #expect(try await h.database.load().reports.map(\.markdown) == [history])
        let requests = await h.access.requests, wires = h.transport.requests
        #expect(requests.count == wires.count && requests.count > 3)
        var stages = Set<String>()
        for (index, wire) in wires.enumerated() {
            let request = requests[index]
            #expect(request.configuration.service == service && request.credential == h.key)
            #expect(wire.url == h.transport.endpoint)
            #expect(wire.value(forHTTPHeaderField: "Authorization") == (service == .messages ? nil : "Bearer \(h.key)"))
            #expect(wire.value(forHTTPHeaderField: "x-api-key") == (service == .messages ? h.key : nil))
            let data = try body(of: wire), text = String(decoding: data, as: UTF8.self)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["model"] as? String == "MODEL_PRIVATE_34")
            #expect(object["store"] as? Bool == (service == .messages ? nil : false))
            #expect(object["truncation"] as? String == (service == .responses ? "disabled" : nil))
            let forbidden = [h.key, h.highConfidenceKey, "SOURCE_ID_PRIVATE_34", "SOURCE_TITLE_PRIVATE_34",
                             "SOURCE_DIRECTORY_PRIVATE_34", "TURN_ID_PRIVATE_34", "UNSAVED_DRAFT_PRIVATE_34"]
            #expect(forbidden.allSatisfy { !text.contains($0) })
            switch request.intent {
            case .probe:
                #expect(index < 3)
                #expect(!text.contains("RAW_WORK_PRIVATE_34") && !text.contains("PREFERENCES_PRIVATE_34") && !text.contains("HISTORY_SAVED_PRIVATE_34"))
            case .extractFacts:
                stages.insert("extracting")
                #expect(!text.contains("HISTORY_SAVED_PRIVATE_34") && !text.contains("INTERMEDIATE_PRIVATE_34"))
            case .mergeFacts:
                stages.insert("merging")
                #expect(text.contains("INTERMEDIATE_PRIVATE_34") && !text.contains("RAW_WORK_PRIVATE_34") && !text.contains("HISTORY_SAVED_PRIVATE_34"))
            case .composeReport:
                stages.insert("composing")
                #expect(text.contains("HISTORY_SAVED_PRIVATE_34") && text.contains("PREFERENCES_PRIVATE_34"))
                #expect(text.contains(batched ? "INTERMEDIATE_PRIVATE_34" : "RAW_WORK_PRIVATE_34"))
            }
        }
        #expect(stages == (batched ? ["extracting", "merging", "composing"] : ["composing"]))
        let rawWorkWires = try wires.dropFirst(3).map { String(decoding: try body(of: $0), as: UTF8.self) }
        #expect(rawWorkWires.contains { $0.contains(h.ordinaryText) })
        let generated = flow.body, sources = flow.generationSources
        let count = wires.count
        let launches = try h.launches
        flow.send(.showSources); flow.send(.setPreview(true))
        let preview = SafeMarkdown.render(generated + "\n![image](https://REMOTE_PREVIEW_PRIVATE_34.invalid/pixel)\n<script>RAW_HTML_PRIVATE_34</script>")
        #expect(!preview.characters.isEmpty && flow.isSourceDrawerVisible)
        #expect(h.transport.requests.count == count)
        #expect(try h.launches == launches)
        flow.send(.copyMarkdown); #expect(h.copies.last == generated)
        await h.access.failNext()
        try await h.generate()
        #expect(flow.generationError == .unavailable && flow.body == generated)
        expectSameSources(flow.generationSources, sources)
        #expect(h.transport.requests.count == count + 1)
        flow.send(.systemWake); await flow.waitForGeneration()
        #expect(h.transport.requests.count == count + 1 && flow.savedAIService.hasMatchingValidation)

        var reader: OpaquePointer?
        #expect(sqlite3_open_v2(h.databaseURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM reports", nil, nil, nil) == SQLITE_OK)
        flow.send(.save); await flow.waitForStorage()
        #expect(flow.storageError == .writeFailed && flow.hasDraft && flow.body == generated)
        expectSameSources(flow.generationSources, sources)
        #expect(sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        flow.send(.save); await flow.waitForStorage()
        #expect(!flow.hasDraft && flow.generationSources == nil)
        let saved = try await h.database.load()
        #expect(saved.reports.contains { $0.day == today && $0.markdown == generated })
        let envelope = try #require(saved.aiServices.configurations[service]?.credential)
        #expect(try await h.credentials.open(envelope) == h.key)
        let forbiddenDisk = [h.key, "RAW_WORK_PRIVATE_34", "INTERMEDIATE_PRIVATE_34", "SOURCE_ID_PRIVATE_34",
                             "SOURCE_TITLE_PRIVATE_34", "SOURCE_DIRECTORY_PRIVATE_34", "TURN_ID_PRIVATE_34", "UNSAVED_DRAFT_PRIVATE_34"]
        try h.expectNoCopies(onDisk: forbiddenDisk)
        flow.send(.requestDeleteReport(today)); flow.send(.confirm(try #require(flow.confirmation).id))
        await flow.waitForStorage()
        #expect(flow.body.isEmpty && flow.confirmedSnapshot == snapshot)
        flow.send(.requestSettingsPage(.contentManagement)); flow.send(.requestClearReports)
        flow.send(.confirm(try #require(flow.confirmation).id)); await flow.waitForStorage()
        #expect(flow.contentCounts == .init(saved: 0, drafts: 0, snapshots: 0))
        #expect(h.copies.last == generated && h.transport.requests.count == count + 1)
        try h.expectNoCopies(onDisk: forbiddenDisk + ["RESULT_PRIVATE_34", "HISTORY_SAVED_PRIVATE_34", h.highConfidenceKey])
        let reportSession = try #require(flow.openWindows[.report])
        flow.send(.requestCloseReport(reportSession)); flow.send(.windowClosed(.report, session: reportSession))
        flow.send(.open(.report)); await flow.waitForStorage()
        #expect(flow.body.isEmpty && flow.confirmedSnapshot == nil && flow.generationSources == nil)
        #expect(h.transport.requests.count == count + 1)
        #expect(try h.launches == launches)
        h.log.flushLog()
        let forbiddenLog = forbiddenDisk + [history, h.highConfidenceKey, "PREFERENCES_PRIVATE_34", "MODEL_PRIVATE_34",
            today.calendarDate, historyDay.calendarDate, today.timeZoneIdentifier, h.transport.endpoint.absoluteString,
            "ENDPOINT_PRIVATE_34", "QUERY_PRIVATE_34", "RAW_ERROR_PRIVATE_34", "RAW_OPTIONAL_ERROR_PRIVATE_34",
            "RESULT_PRIVATE_34", envelope.combined.base64EncodedString(), h.environment.credentialKey.base64EncodedString(),
            SHA256.hash(data: Data("SOURCE_ID_PRIVATE_34".utf8)).map { String(format: "%02x", $0) }.joined()]
        try expectOnlyWhitelistedTelemetry(h.memory.snapshot(), forbidden: forbiddenLog)
        #expect(h.memory.snapshot().contains { $0.message.contains("result=failure") })
        #expect(h.memory.logFormatter == nil)
        await h.database.close()
        let reopened = DailyReportDatabase(directory: h.storageDirectory)
        let restored = try await reopened.load()
        #expect(restored.reports.isEmpty && restored.aiServices.current == service)
        #expect(restored.aiServices.configurations[service]?.credential == envelope)
        await reopened.close()
    }

    @Test(arguments: AIServiceType.allCases)
    func redactionFailureContinuesWithoutRewritingSnapshotsOrManualText(_ service: AIServiceType) async throws {
        let h = try PrivacyFlowHarness(streaming: false, redactionFails: true)
        defer { h.transport.close(); h.environment.close() }
        try await h.prepare(service, batched: false)
        let flow = h.flow!, snapshot = try #require(flow.confirmedSnapshot)
        #expect(snapshot.redactionFailed && snapshot.sessions[0].turns[0].userText.contains(h.key))
        try await h.generate()
        #expect(flow.hasDraft && flow.generationRedactionFailed && flow.generationError == nil)
        #expect(flow.confirmedSnapshot == snapshot && !flow.body.contains(h.key))
        let text = String(decoding: try body(of: try #require(h.transport.requests.last)), as: UTF8.self)
        #expect(text.contains("RAW_WORK_PRIVATE_34") && text.contains(h.highConfidenceKey) && !text.contains(h.key))
        #expect(text.contains(h.ordinaryText))
        let manual = "MANUAL_PRIVATE_34 \(h.key) \(h.highConfidenceKey)"
        try h.edit(manual); flow.send(.copyMarkdown); flow.send(.save); await flow.waitForStorage()
        #expect(flow.body == manual && h.copies == [manual] && flow.generationSources == nil)
        #expect(try await h.database.load().reports.first?.markdown == manual)
        flow.send(.requestSettingsPage(.aiServices)); flow.send(.showAICredential); await flow.waitForAICredential()
        #expect(flow.revealedAICredential == h.key)
        flow.send(.hideAICredential); flow.send(.copyAICredential); await flow.waitForAICredential()
        #expect(flow.revealedAICredential == nil && h.copies == [manual, h.key])
        let savedDay = flow.selectedDay
        flow.send(.moveDate(1))
        try h.install(syntheticCandidate("NEXT_SOURCE_PRIVATE_34", user: "NEXT_WORK_PRIVATE_34", day: flow.selectedDay))
        flow.send(.scanSessions); await flow.waitForSessionScan()
        flow.send(.confirmSessionSelection); await flow.waitForSessionScan()
        try await h.generate()
        let historyWire = String(decoding: try body(of: try #require(h.transport.requests.last)), as: UTF8.self)
        #expect(flow.generationError == nil && flow.generationRedactionFailed)
        #expect(flow.generationSources?.historyDays == [savedDay])
        #expect(historyWire.contains("MANUAL_PRIVATE_34") && !historyWire.contains(h.key))
        #expect(try await h.database.load().reports.first?.markdown == manual)
        #expect(h.copies == [manual, h.key])
        h.log.flushLog()
        try expectOnlyWhitelistedTelemetry(h.memory.snapshot(), forbidden: [h.key, h.highConfidenceKey, manual, "RAW_WORK_PRIVATE_34"])
        await h.database.close()
    }

    private func expectSameSources(_ actual: ReportGenerationSources?, _ expected: ReportGenerationSources?) {
        #expect(actual?.groups.map(\.directory) == expected?.groups.map(\.directory))
        #expect(actual?.groups.map(\.titles) == expected?.groups.map(\.titles))
        #expect(actual?.historyDays == expected?.historyDays)
    }
}
