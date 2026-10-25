import CocoaLumberjack
import Foundation
import Testing

// The public diagnostic contract is an independent allowlist, not a snapshot
// generated from the production formatter. Reject extra fields as well as secrets.
func expectOnlyWhitelistedTelemetry(_ messages: [DDLogMessage], forbidden: [String] = []) throws {
    for message in messages {
        let event = try #require(message.function)
        let format: String
        let fields: [String: String]
        switch event {
        case "window_mode_changed":
            format = "window_mode_changed mode=%@"
            fields = ["mode": "foreground|menu_bar"]
        case "codex_check_finished":
            format = "codex_check_finished result=%@ error=%@ version=%@"
            fields = ["result": "success|failure|cancelled",
                      "error": "none|executable_missing|invalid_executable|executable_permission|directory_missing|invalid_directory|directory_permission|launch_failed|handshake_failed|read_failed|method_unsupported|parameters_unsupported|schema_unsupported|transport_interrupted|timed_out|cancelled|scan_lock_unavailable|scan_lock_timed_out",
                      "version": "unknown|[0-9]+\\.[0-9]+\\.[0-9]+"]
        case "session_scan_finished":
            format = "session_scan_finished result=%@ candidates=%d succeeded=%d failed=%d"
            fields = ["result": "complete|partial|failure|cancelled", "candidates": "[0-9]+", "succeeded": "[0-9]+", "failed": "[0-9]+"]
        case "report_storage_finished":
            format = "report_storage_finished operation=%@ result=%@ schema=%d credential_format=%d"
            fields = ["operation": "configuration|currentSelection|credentialDeletion|reportDeletion|reportClear|reset",
                      "result": "success|failure", "schema": "5", "credential_format": "2"]
        case "ai_validation_finished":
            format = "ai_validation_finished service=%@ stage=%@ result=%@ capability=%@"
            fields = ["service": "chatCompletions|responses|messages", "stage": "basic|streaming|structured",
                      "result": "success|failure|unfinished|cancelled", "capability": "supported|unsupported|unknown"]
        case "report_generation_started", "report_generation_stage_changed", "report_generation_finished":
            format = event + " path=%@ stage=%@ result=%@ input_tokens=%d reason=%@ plan_min=%d plan_max=%d layer=%d completed=%d in_flight=%d tokenizer=0.12.1"
            fields = ["path": "planning|direct|batched", "stage": "planning|awaitingConfirmation|extracting|merging|composing",
                      "result": "running|success|degraded|failure|cancelled", "input_tokens": "[0-9]+",
                      "reason": "none|network|timeout|cancelled|authentication|model|parameters|contextLimit|rateLimit|quota|serviceLimit|redirect|unavailable|unknown|invalidResponse|incomplete|refusal|unsupportedService|tokenizer|budget|missingInput|missingConfiguration|streamingUnsupported|structuredUnsupported",
                      "plan_min": "[0-9]+", "plan_max": "[0-9]+", "layer": "[0-9]+", "completed": "[0-9]+",
                      "in_flight": "[0-9]+", "tokenizer": "0\\.12\\.1"]
        default:
            Issue.record("Unexpected daily-report telemetry event: \(event)")
            continue
        }
        let components = message.message.split(separator: " ", omittingEmptySubsequences: false)
        #expect(components.first.map(String.init) == event)
        let pairs = components.dropFirst().map { $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false) }
        #expect(pairs.count == fields.count)
        #expect(Set(pairs.compactMap { $0.first.map(String.init) }) == Set(fields.keys))
        for pair in pairs {
            #expect(pair.count == 2)
            guard pair.count == 2, let pattern = fields[String(pair[0])] else { continue }
            #expect(String(pair[1]).range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil)
        }
        #expect(message.messageFormat == format)
        #expect(message.file == "DailyReports" && message.fileName == "DailyReports")
        #expect(message.line == 0 && message.context == 0 && message.representedObject == nil)
        #expect(message.level == .info && message.flag == .info && message.options.isEmpty)
        let strings = [message.message, message.messageFormat, message.file, message.fileName, event,
                       message.threadID, message.threadName ?? "", message.queueLabel]
        #expect(forbidden.allSatisfy { marker in strings.allSatisfy { !$0.contains(marker) } })
    }
}
