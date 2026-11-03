import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct LiveOpenAISemanticTests {
    @Test(arguments: [AIServiceType.chatCompletions, .responses])
    func liveConfigurationUsesTheRequestedLunaModelWithTheExistingControls(_ service: AIServiceType) {
        let configuration = liveOpenAIConfiguration(service)
        #expect(configuration.model == "gpt-6-luna")
        #expect(configuration.endpoint == service.endpointExample && configuration.outputLimit == 3_000)
        switch configuration.defaults {
        case .chatCompletions(let controls): #expect(controls.reasoningEffort == AIReasoningEffort.none)
        case .responses(let controls): #expect(controls.reasoningEffort == AIReasoningEffort.none)
        case .messages: Issue.record("Unexpected protocol")
        }
    }

    @Test func extractionPairStopsBeforeSendingAMergeOrCompositionRequest() async throws {
        for intent in [AIRequestIntent.mergeFacts, .composeReport] {
            let access = LiveOpenAIAccess(requestLimit: 0, extractionOnly: true)
            let request = AIRequest(intent: intent, configuration: liveOpenAIConfiguration(.responses),
                credential: "SYNTHETIC_NO_NETWORK_KEY", instruction: "synthetic", input: "{}", schema: nil, streaming: false)
            await #expect(throws: LiveOpenAIError.extractionComplete) { try await access.execute(request) }
            #expect(await access.records.isEmpty)
        }
    }

    @Test func causalitySignalsRejectTheObservedReleaseCauseWithoutRejectingSeparateBlockers() {
        #expect(hasCrossedS08BlockerCause("Release remains blocked by missing synthetic sign-off and unresolved synthetic schema mismatch."))
        #expect(hasCrossedS08BlockerCause("The schema mismatch blocks release."))
        #expect(!hasCrossedS08BlockerCause("The shared synthetic schema mismatch blocks integrating these rules. The synthetic sign-off is still missing; release remains blocked."))
        #expect(!hasCrossedS08BlockerCause("Schema mismatch blocks integration; missing sign-off blocks release."))
        #expect(!hasCrossedS08BlockerCause("Schema mismatch blocks integration and missing sign-off blocks release."))
    }

    @Test func riskInventorySignalDistinguishesGroupedStatusesFromRepeatedOutputs() throws {
        let source = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
        let inventory = source.sessions.dropFirst().flatMap(\.turns).compactMap(\.finalAnswer).joined(separator: "\n")
        #expect(hasFullS08RiskInventory("## Issues & Risks\n\n" + inventory))
        #expect(!hasFullS08RiskInventory("## Issues & Risks\n\nRules SYNTH36-08-B01-1 through SYNTH36-08-B16-4 remain pending review."))
        #expect(!hasFullS08RiskInventory("## Completed Work\n\n" + inventory + "\n\n## Issues & Risks\n\nApproval remains missing."))
    }

    @Test func signOffScopeSignalsDistinguishProgressIdentityFromCausalScope() {
        #expect(hasNarrowedSignOffScope(["The synthetic sign-off is still missing; release remains blocked for SYNTH36-08-B16-4."]))
        #expect(hasNarrowedSignOffScope(["For SYNTH36-08-B16-4, the synthetic sign-off is still missing; release remains blocked."]))
        #expect(!hasNarrowedSignOffScope(["The synthetic sign-off is still missing; release remains blocked."]))
        #expect(!hasNarrowedSignOffScope(["Drafted the configuration rule for SYNTH36-08-B16-4; review remains pending. The synthetic sign-off is still missing; release remains blocked."]))
    }

    @Test func s08PlanningStaysWithinTheTargetedLiveCaps() async throws {
        let original = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
        for type in [AIServiceType.chatCompletions, .responses] {
            var service = SavedAIService(configuration: liveOpenAIConfiguration(type))
            service.validation.structured = .supported
            let plan = try await LivePlan.make(original, service: service, credential: "SYNTHETIC_S08_PLAN_KEY")
            #expect(plan.maximumRequests <= 9 && plan.extractionRequests > 1)
            print("S08 OFFLINE \(type.rawValue) generation=\(plan.minimumRequests)...\(plan.maximumRequests) extract=\(plan.extractionRequests) merge-layers<=\(plan.maximumMergeLayers)")
            let layered = try await LivePlan.make(original.layeredBudget(), service: service, credential: "SYNTHETIC_S08_PLAN_KEY")
            #expect(layered.totalBudget == 9_550 && layered.outputLimit == 3_000)
            #expect(layered.extractionRequests == 16 && layered.maximumMergeLayers == 3 && layered.maximumRequests <= 31)
            #expect(layered.auxiliaryClippedDuringExtraction)
            if type == .chatCompletions {
                for local in [false, true] {
                    let minimum = try await LivePlan.make(original.blockerScopeMinimum(explicitlyLocal: local),
                        service: service, credential: "SYNTHETIC_S08_PLAN_KEY")
                    #expect(minimum.minimumRequests == 1 && minimum.maximumRequests == 1 && minimum.path == "direct")
                    let state = try await LivePlan.make(original.stateScopeMinimum(explicitlyLocal: local),
                        service: service, credential: "SYNTHETIC_S08_PLAN_KEY")
                    #expect(state.minimumRequests == 1 && state.maximumRequests == 1 && state.path == "direct")
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_LIVE_OPENAI"] == "1"))
    func officialOpenAIProtocols() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard let key = variables["OPENAI_API_KEY"], !key.isEmpty,
              let output = variables["RANDOM_THOUGHTS_LIVE_OUTPUT"] else {
            throw LiveOpenAIError.missingEnvironment
        }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        let mode = variables["RANDOM_THOUGHTS_LIVE_MODE"]
        print("LIVE TARGET model=\(LiveOpenAITarget.model) reasoning=none outputLimit=3000")
        let minimumScope = mode == "s08-minimum"
        let stateScopeMinimum = mode == "s08-state-minimum"
        let layeredScope = mode == "s08-layered"
        let mergeMinimum = mode == "s08-merge-minimum"
        let compositionComponent = mode == "s08-composition"
        let mergeBudget = mode == "s08-merge-budget"
        let extractionPair = mode == "s08-extraction-pair"
        let extractionBaseline = mode == "s08-extraction-baseline"
        let parentReferences = mode == "s08-parent-references"
        let repetitions = minimumScope || stateScopeMinimum ? 1 : 2
        var qualifiedServices: [SavedAIService] = []
        let protocols: [AIServiceType]
        if compositionComponent || mergeBudget || extractionPair || extractionBaseline || parentReferences { protocols = [.responses] }
        else if minimumScope || stateScopeMinimum || mergeMinimum { protocols = [.chatCompletions] }
        else { protocols = [.chatCompletions, .responses] }
        for service in protocols {
            let access = LiveOpenAIAccess(requestLimit: 3)
            let environment = ReportFlowTestEnvironment()
            environment.aiAccess = access
            let flow = environment.makeFlow()
            flow.send(.open(.report)); flow.send(.open(.settings))
            await flow.waitForStorage()
            flow.send(.requestSettingsPage(.aiServices)); flow.send(.selectAIServiceType(service))
            var edit = flow.aiServiceEdit
            edit.configuration = liveOpenAIConfiguration(service)
            edit.totalBudget = "65536"; edit.outputLimit = "3000"; edit.concurrency = "3"
            edit.newCredential = key
            flow.send(.editAIService(edit, session: try #require(flow.openWindows[.settings]), revision: flow.aiServiceEditRevision))
            flow.send(.saveAIService); await flow.waitForStorage()
            flow.send(.requestAIValidation); await flow.waitForAIValidation()
            let records = await access.records
            try JSONEncoder().encode(records).write(to: root.appendingPathComponent("\(service.rawValue)-probes.json"))
            let qualified = flow.savedAIService.hasMatchingValidation
            print("LIVE \(service.rawValue) probes=\(records.count) qualified=\(qualified) errors=\(records.compactMap(\.error))")
            #expect(qualified)
            guard qualified else { return }
            if extractionBaseline || parentReferences {
                let frozenCapabilities = records.count == 3 && records.allSatisfy { $0.error == nil }
                    && flow.savedAIService.validation.streaming == .supported
                    && flow.savedAIService.validation.structured == .supported
                #expect(frozenCapabilities)
                guard frozenCapabilities else { return }
            }
            qualifiedServices.append(flow.savedAIService)
        }
        if parentReferences {
            try await runS08ParentReferences(service: #require(qualifiedServices.first), key: key, root: root)
            return
        }
        if extractionBaseline {
            try await runS08ExtractionBaseline(service: #require(qualifiedServices.first), key: key, root: root)
            return
        }
        if extractionPair {
            try await runS08ExtractionPair(service: #require(qualifiedServices.first), key: key, root: root)
            return
        }
        if compositionComponent {
            try await runS08CompositionComponents(service: #require(qualifiedServices.first), key: key, root: root)
            return
        }
        if mergeBudget {
            try await runS08MergeBudgetPair(service: #require(qualifiedServices.first), key: key, root: root)
            return
        }
        if mergeMinimum {
            let source = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
            var service = try #require(qualifiedServices.first)
            service.configuration.totalBudget = try source.layeredBudget().totalBudget
            let context = ReportGenerationContext(service: service,
                snapshot: .init(day: source.day, sessions: source.sessions, redactionFailed: false),
                settings: source.settings, history: source.history)
            guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: key,
                tokenizer: OfflineReportTokenizer(), redact: { $0 }) else { throw LiveOpenAIError.unexpectedConfiguration }
            let step = try #require(plan.mergeLayers.first?.first { step in
                let fragmentIDs = Set(plan.extraction.filter { step.upstream.contains($0.id) }.flatMap(\.fragments).map(\.id))
                return Set(step.upstream).isDisjoint(with: fragmentIDs)
            })
            let parents = plan.extraction.filter { step.upstream.contains($0.id) }
            guard parents.count == 2 else { throw LiveOpenAIError.unexpectedConfiguration }
            let access = LiveOpenAIAccess(requestLimit: 3)
            var blocks: [String] = []
            print("LIVE COMPONENT generation HTTP=3; two extraction nodes then one merge; no automatic retries")
            for parent in parents {
                let response = try await recordedComponentRequest(.init(intent: .extractFacts, configuration: service.configuration,
                    credential: key, instruction: plan.factInstruction, input: parent.input, schema: plan.factSchema,
                    streaming: service.validation.streaming == .supported), access: access,
                    output: root.appendingPathComponent("merge-minimum.json"))
                let facts = try ReportFactPayload.parse(response)
                let turns = Set(facts.facts.flatMap(\.turns)).intersection(Set(parent.fragments.map(\.association)))
                blocks.append(try ReportJSON.encode(ReportFactNode.Input(id: parent.id, facts: facts.facts,
                    noRelevantContent: facts.noRelevantContent, completeTurns: turns.sorted())))
            }
            let response = try await recordedComponentRequest(.init(intent: .mergeFacts, configuration: service.configuration,
                credential: key, instruction: plan.factInstruction, input: step.input, schema: plan.factSchema,
                streaming: service.validation.streaming == .supported, additionalInputs: blocks), access: access,
                output: root.appendingPathComponent("merge-minimum.json"))
            let payload = try ReportFactPayload.parse(response)
            let expected = Set(step.upstream)
            let covered = payload.covered.count == expected.count && Set(payload.covered) == expected
            let references = payload.facts.allSatisfy { !$0.references.isEmpty && Set($0.references).isSubset(of: expected) }
            let retained = expected.isSubset(of: Set(payload.facts.flatMap(\.references)))
            let associations = payload.facts.allSatisfy { fact in
                let turns = Set(parents.filter { fact.references.contains($0.id) }.flatMap(\.fragments).map(\.association))
                return !fact.turns.isEmpty && Set(fact.turns).isSubset(of: turns)
            }
            print("LIVE COMPONENT covered=\(covered) references=\(references) parentsRetained=\(retained) associations=\(associations) facts=\(payload.facts.count)")
            #expect(covered && references && retained && associations)
            return
        }
        if stateScopeMinimum {
            let original = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
            var service = try #require(qualifiedServices.first)
            service.configuration.totalBudget = original.totalBudget
            let context = ReportGenerationContext(service: service,
                snapshot: .init(day: original.day, sessions: original.sessions, redactionFailed: false),
                settings: original.settings, history: original.history)
            guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: key,
                tokenizer: OfflineReportTokenizer(), redact: { $0 }) else { throw LiveOpenAIError.unexpectedConfiguration }
            let step = try #require(plan.extraction.first { $0.fragments.contains { ($0.finalAnswer ?? "").contains("sign-off") } })
            let inputs = try [false, true].map { local in
                let fragments = try step.fragments.map { fragment in
                    let turn = try #require(plan.prepared.today.first { $0.session == fragment.session && $0.order == fragment.order })
                    let answer = local ? turn.finalAnswer?.replacingOccurrences(
                        of: "The synthetic sign-off is still missing; release remains blocked.",
                        with: ReportAcceptanceScenario.localSignOffScope) : turn.finalAnswer
                    let reduced = ReportInputTurn(session: turn.session, order: turn.order, date: turn.date,
                        timeZone: turn.timeZone, result: turn.result, user: turn.user,
                        finalAnswer: answer, startedAt: turn.startedAt)
                    return ReportInputFragment(id: fragment.id, turn: reduced, part: 1, parts: 1,
                        user: reduced.user, finalAnswer: reduced.finalAnswer)
                }
                return try plan.input(fragments: fragments)
            }
            let access = LiveOpenAIAccess(requestLimit: inputs.count)
            guard inputs.count == 2 else { throw LiveOpenAIError.unexpectedConfiguration }
            print("LIVE COMPONENT generation HTTP=2; sign-off extraction pair; no automatic retries")
            for (index, input) in inputs.enumerated() {
                let response = try await recordedComponentRequest(AIRequest(intent: .extractFacts,
                    configuration: service.configuration, credential: key, instruction: plan.factInstruction,
                    input: input, schema: plan.factSchema, streaming: service.validation.streaming == .supported),
                    access: access, output: root.appendingPathComponent("signoff-extract.json"))
                let payload = try ReportFactPayload.parse(response)
                let facts = payload.facts.map { $0.summary.lowercased() }.filter { $0.contains("sign-off") }
                let scopePreserved = !facts.isEmpty && (index == 1
                    ? facts.contains { $0.contains("only") && $0.contains("b16-4") && $0.contains("other rules") }
                    : !hasNarrowedSignOffScope(facts))
                print("LIVE COMPONENT case=\(index) scopeSignal=\(scopePreserved)")
                #expect(scopePreserved)
            }
        }
        guard mode == "scenarios" || mode == "invalid-response" || mode == "s07-plans"
                || mode == "s08-blockers" || minimumScope || stateScopeMinimum || layeredScope else { return }
        let all = try ReportAcceptanceScenario.loadAll()
        let scenarios: [ReportAcceptanceScenario]
        if minimumScope {
            let original = try #require(all.first { $0.id == "S08" })
            scenarios = try [false, true].map { try original.blockerScopeMinimum(explicitlyLocal: $0) }
        } else if stateScopeMinimum {
            let original = try #require(all.first { $0.id == "S08" })
            scenarios = try [false, true].map { try original.stateScopeMinimum(explicitlyLocal: $0) }
        } else if layeredScope {
            scenarios = [try #require(all.first { $0.id == "S08" }).layeredBudget()]
        } else { scenarios = all }
        let selected = qualifiedServices.flatMap { service in
            scenarios.filter { scenario in
                if minimumScope || stateScopeMinimum || layeredScope { return true }
                if mode == "s08-blockers" { return scenario.id == "S08" }
                return mode == "scenarios" || scenario.id == "S07"
                    || (mode == "invalid-response" && service.configuration.service == .chatCompletions && scenario.id == "S08")
            }.map { (service, $0) }
        }
        var plans: [String: LivePlan] = [:]
        for (service, scenario) in selected {
            let plan = try await LivePlan.make(scenario, service: service, credential: key)
            plans[plan.id] = plan
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plans).write(to: root.appendingPathComponent("plans.json"))
        let minimum = plans.values.reduce(0) { $0 + $1.minimumRequests * repetitions }
        let maximum = plans.values.reduce(0) { $0 + $1.maximumRequests * repetitions }
        if minimumScope, maximum != 2 { throw LiveOpenAIError.unexpectedConfiguration }
        if mode == "s08-blockers", maximum > 36 { throw LiveOpenAIError.unexpectedConfiguration }
        if stateScopeMinimum, maximum != 2 { throw LiveOpenAIError.unexpectedConfiguration }
        if layeredScope, maximum > 124 { throw LiveOpenAIError.unexpectedConfiguration }
        print("LIVE PLAN generation HTTP=\(minimum)...\(maximum); tasks=\(selected.count * repetitions); no automatic retries")
        for (service, scenario) in selected {
            let plan = try #require(plans["\(service.configuration.service.rawValue)-\(scenario.id)"])
            for repetition in 1...repetitions {
                let id = "\(plan.id)-\(repetition)"
                let access = LiveOpenAIAccess(requestLimit: plan.maximumRequests)
                let environment = ReportFlowTestEnvironment()
                environment.aiAccess = access
                let flow = try await scenario.prepare(environment: environment, service: service)
                let started = Date()
                flow.send(.generateReport); await flow.waitForGeneration()
                if let confirmation = flow.confirmation {
                    // The user authorized this finite live acceptance run before any paid generation.
                    guard confirmation.generationScale?.maximumRequests == plan.maximumRequests else {
                        throw LiveOpenAIError.unexpectedConfiguration
                    }
                    flow.send(.confirm(confirmation.id)); await flow.waitForGeneration()
                }
                let requests = await access.records
                let result = environment.generationEvents.last
                let record = LiveTaskRecord(id: id, plan: plan, seconds: Date().timeIntervalSince(started),
                    error: flow.generationError?.rawValue, result: result?.result.rawValue ?? "unfinished",
                    actualPath: result?.path.rawValue ?? "planning", actualMergeLayers: result?.layer ?? 0,
                    historyDays: flow.generationSources?.historyDays.map(\.calendarDate) ?? [], requests: requests)
                try encoder.encode(record).write(to: root.appendingPathComponent("\(id).json"))
                if flow.hasDraft {
                    guard !flow.body.contains(key) else { throw LiveOpenAIError.unexpectedConfiguration }
                    // String's atomic writer may create an item-replacement directory outside this sandbox.
                    try Data(flow.body.utf8).write(to: root.appendingPathComponent("\(id).md"))
                }
                print("LIVE \(id) result=\(record.result) error=\(record.error ?? "none") HTTP=\(requests.count) layers=\(record.actualMergeLayers)")
                #expect(flow.hasDraft && flow.generationError == nil)
                if mode == "s08-blockers" || layeredScope {
                    #expect(!hasCrossedS08BlockerCause(flow.body))
                    #expect(!hasFullS08RiskInventory(flow.body))
                }
                if stateScopeMinimum || mode == "s08-blockers" || layeredScope {
                    expectS08SignOffSignals(flow.body, explicitlyLocal: scenario.id == "S08-state-local")
                    expectS08CompletionSignals(flow.body)
                }
                if mode == "s08-blockers" || minimumScope || layeredScope {
                    expectS08ScopeSignals(flow.body, explicitlyLocal: scenario.id == "S08-local")
                }
                if layeredScope {
                    #expect(record.actualMergeLayers >= 2)
                    let extraction = requests.filter { $0.intent == "extract" }
                    #expect(extraction.reduce(0) { $0 + $1.userBytes } == scenario.userBytes)
                    #expect(extraction.reduce(0) { $0 + $1.answerBytes } == scenario.answerBytes)
                }
                if mode == "s07-plans" {
                    let plans = flow.body.components(separatedBy: "## 明日计划\n\n").last
                    // A verbatim source status in the wrong section is a degradation, not a new action.
                    // Other wording requires manual review; this is not a general semantic validator.
                    #expect(plans == "无明确内容" || plans == "- 四项隔离测试尚未执行。")
                }
                // Configuration/credit failures invalidate every dependent task; do not spend more on them.
                if let error = flow.generationError, error.invalidatesConfiguration || error == .quota || error == .serviceLimit { return }
            }
        }
    }
}

private enum LiveOpenAIError: Error, Equatable { case missingEnvironment, unexpectedConfiguration, extractionComplete }

@MainActor
private func makeS08LayeredPlan(service qualified: SavedAIService, key: String) async throws -> ReportBatchPlan {
    let source = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" }).layeredBudget()
    var service = qualified; service.configuration.totalBudget = source.totalBudget
    let context = ReportGenerationContext(service: service,
        snapshot: .init(day: source.day, sessions: source.sessions, redactionFailed: false),
        settings: source.settings, history: source.history)
    guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: key,
        tokenizer: OfflineReportTokenizer(), redact: { $0 }) else { throw LiveOpenAIError.unexpectedConfiguration }
    return plan
}

@MainActor
private func runS08ExtractionBaseline(service qualified: SavedAIService, key: String, root: URL) async throws {
    let plan = try await makeS08LayeredPlan(service: qualified, key: key)
    let access = LiveOpenAIAccess(requestLimit: 32, extractionOnly: true)
    print("LIVE EXTRACTION BASELINE generation HTTP<=32; original 16 nodes x 2 independent rounds; stop on failure; no retries, merges or composition")
    let result = await S08ExtractionAcceptance.run(plan: plan, credential: key, access: access)
    let records = await access.records
    try JSONEncoder().encode(records).write(to: root.appendingPathComponent("extraction-baseline.json"))
    try JSONEncoder().encode(result).write(to: root.appendingPathComponent("extraction-baseline-diagnostics.json"))
    for round in result.rounds {
        let returned = round.nodes.filter(\.returned).count
        let rejected = round.nodes.filter { $0.observation.rejections.contains { $0.predicate == .turnAssociation } }.count
        print("LIVE EXTRACTION BASELINE repetition=\(round.repetition) status=\(round.status.rawValue) dispatched=\(round.nodes.filter(\.dispatched).count)/16 returned=\(returned) accepted=\(round.nodes.filter { $0.accepted == true }.count) retained=\(round.nodes.filter { $0.retained == true }.count) association-rejections=\(rejected)/\(returned)")
    }
    print("LIVE EXTRACTION BASELINE HTTP=\(records.count) admitted=\(result.admitted); extraction gate only")
    #expect(result.admitted)
}

@MainActor
private func runS08ParentReferences(service qualified: SavedAIService, key: String, root: URL) async throws {
    let plan = try await makeS08LayeredPlan(service: qualified, key: key)
    let access = LiveOpenAIAccess(requestLimit: 8)
    print("LIVE PARENT REFERENCES generation HTTP<=8; parents 15/16 then fixed 6 independent merges at node24; no retry, composition or full S08")
    let result = await S08ParentReferenceDiagnostics.run(plan: plan, credential: key, access: access)
    let records = await access.records
    try JSONEncoder().encode(records).write(to: root.appendingPathComponent("parent-references.json"))
    try JSONEncoder().encode(result).write(to: root.appendingPathComponent("parent-reference-diagnostics.json"))
    let returned = result.attempts.filter { $0.result.returned }.count
    let rejected = result.attempts.filter { $0.result.observation.rejections.contains { $0.predicate == .nonemptyParents } }.count
    for attempt in result.attempts {
        let record = attempt.result
        print("LIVE PARENT REFERENCES repetition=\(attempt.repetition) dispatched=\(record.dispatched) returned=\(record.returned) accepted=\(record.accepted.map(String.init) ?? "undetermined") retained=\(record.retained.map(String.init) ?? "undetermined") predicates=\(record.observation.rejections.map { $0.predicate.rawValue }) error=\(record.error ?? "none")")
    }
    print("LIVE PARENT REFERENCES HTTP=\(records.count) ready=\(result.ready) complete=\(result.complete) nonemptyParents=\(rejected)/\(returned) returned; reproduction only")
    #expect(result.ready && result.complete)
    #expect(rejected == 0)
}

@MainActor
private func runS08ExtractionPair(service qualified: SavedAIService, key: String, root: URL) async throws {
    let original = try await makeS08LayeredPlan(service: qualified, key: key)
    let plan = try S08ExtractionPair.makePlan(from: original)
    let access = LiveOpenAIAccess(requestLimit: 2, extractionOnly: true)
    var attempts: [S08ExtractionDiagnostics.Attempt] = []
    print("LIVE EXTRACTION PAIR generation HTTP<=2; fragments 22/23, turns 7/1 and 7/2; no retries, merges or composition")
    for repetition in 1...2 {
        var complete = false, error: AIRequestError?
        let diagnostics = S08ExtractionDiagnostics()
        do {
            _ = try await ReportBatchExecutor(plan: plan, credential: key,
                access: S08ExtractionDiagnosticAccess(upstream: access, diagnostics: diagnostics),
                redact: { $0 }, progress: { _ in }, onRejection: { diagnostics.reject($0) }).execute()
        } catch LiveOpenAIError.extractionComplete { complete = true }
        catch let caught { error = AIRequestError.reason(for: caught) }
        let records = await access.records
        try JSONEncoder().encode(records).write(to: root.appendingPathComponent("extraction-pair.json"))
        attempts.append(.init(repetition: repetition, accepted: complete, error: error?.rawValue, observation: diagnostics.observation))
        try JSONEncoder().encode(attempts).write(to: root.appendingPathComponent("extraction-pair-diagnostics.json"))
        print("LIVE EXTRACTION PAIR repetition=\(repetition) HTTP=\(records.count) accepted=\(complete) error=\(error?.rawValue ?? "none")")
        let returned = attempts.filter { $0.accepted || !$0.observation.rejections.isEmpty }.count
        let rejected = attempts.filter { $0.observation.rejections.contains { $0.predicate == .turnAssociation } }.count
        print("LIVE EXTRACTION PAIR association-rejections=\(rejected)/\(returned) returned; attempted=\(attempts.count)/2")
        #expect(complete && error == nil)
        if let error, error.invalidatesConfiguration || error == .quota || error == .serviceLimit { return }
    }
}

@MainActor
private func runS08MergeBudgetPair(service qualified: SavedAIService, key: String, root: URL) async throws {
    let plan = try await makeS08LayeredPlan(service: qualified, key: key)
    let service = plan.prepared.context.service
    let sessions = plan.prepared.context.snapshot.sessions
    let tokenizer = OfflineReportTokenizer(), access = LiveOpenAIAccess(requestLimit: 2)
    var blocks: [String] = []
    var parentTurns: [Int: Set<String>] = [:], parentTokens = 0
    for (group, range) in [(25, 0...4), (26, 5...8)] {
        var facts: [ReportFactPayload.Fact] = []
        for session in range {
            for (order, turn) in sessions[session].turns.enumerated() {
                let answer = try #require(turn.finalAnswer)
                let association = "\(session + 1)/\(order + 1)"
                let blocker = " The shared synthetic schema mismatch blocks integrating these rules."
                facts.append(.init(references: [group], turns: [association], status: session == 0 ? .confirmed : .unconfirmed,
                    summary: answer.replacingOccurrences(of: blocker, with: "")))
                if answer.contains(blocker) {
                    facts.append(.init(references: [group], turns: [association], status: .unconfirmed,
                        summary: "The shared synthetic schema mismatch blocks integrating these rules; affected scope unspecified."))
                }
            }
        }
        try #require(facts.count == 17)
        parentTurns[group] = Set(facts.flatMap(\.turns))
        let block = try ReportJSON.encode(ReportFactNode.Input(id: group, facts: facts, noRelevantContent: false,
            completeTurns: Array(Set(facts.flatMap(\.turns))).sorted()))
        let size = try await tokenizer.count(block)
        try #require(size <= plan.visibleLimit)
        parentTokens += size
        print("LIVE PAIR parent=\(group) normalized=\(size) facts=\(facts.count)")
        blocks.append(block)
    }
    for repetition in 1...2 {
        let payload = try await recordedComponentRequest(.init(intent: .mergeFacts, configuration: service.configuration,
            credential: key, instruction: plan.factInstruction, input: plan.input(upstream: [25, 26]), schema: plan.factSchema,
            streaming: service.validation.streaming == .supported, additionalInputs: blocks), access: access,
            output: root.appendingPathComponent("budget-pair.json"))
        let facts = try ReportFactPayload.parse(payload)
        let normalized = try ReportJSON.encode(ReportFactNode.Input(id: 29, facts: facts.facts, noRelevantContent: facts.noRelevantContent,
            completeTurns: Array(Set(facts.facts.flatMap(\.turns))).sorted()))
        let raw = try await tokenizer.count(payload), count = try await tokenizer.count(normalized)
        let retained = Set(facts.facts.flatMap(\.references)).isSuperset(of: [25, 26])
        let covered = facts.covered.count == 2 && Set(facts.covered) == [25, 26] && !facts.noRelevantContent
        let associations = facts.facts.allSatisfy { fact in
            let references = Set(fact.references), turns = Set(fact.turns)
            let valid = references.reduce(into: Set<String>()) { $0.formUnion(parentTurns[$1] ?? []) }
            return !references.isEmpty && references.count == fact.references.count && references.isSubset(of: [25, 26])
                && !turns.isEmpty && turns.count == fact.turns.count && turns.isSubset(of: valid)
        }
        let turnsPreserved = Set(facts.facts.flatMap(\.turns)) == parentTurns.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        print("LIVE PAIR repetition=\(repetition) raw=\(raw) normalized=\(count) retained=\(retained) facts=\(facts.facts.count) covered=\(covered) associations=\(associations) turnsPreserved=\(turnsPreserved)")
        #expect(raw <= plan.visibleLimit && count <= plan.visibleLimit && count < parentTokens && retained)
        #expect(covered && associations && turnsPreserved)
    }
}


// Fixed observed English clauses, not a general semantic validator or a product filter.
private func hasCrossedS08BlockerCause(_ report: String) -> Bool {
    report.lowercased().range(of: #"release[^.;\n]*(?:blocked by|blocked due to)[^.;\n]*schema|schema(?: mismatch)?\s+(?:blocks|prevents|stops)\s+(?:the\s+)?release"#,
        options: .regularExpression) != nil
}

// This catches the observed full v1 inventory, not all excessive repetition.
private func hasFullS08RiskInventory(_ report: String) -> Bool {
    let risks = report.lowercased().components(separatedBy: "## issues & risks\n\n").last?
        .components(separatedBy: "\n\n## tomorrow’s plan").first ?? ""
    return (1...16).allSatisfy { family in
        (1...4).allSatisfy { risks.contains(String(format: "synth36-08-b%02d-%d", family, $0)) }
    }
}

@MainActor
private func runS08CompositionComponents(service qualified: SavedAIService, key: String, root: URL) async throws {
    let source = try #require(ReportAcceptanceScenario.loadAll().first { $0.id == "S08" })
    var service = qualified
    service.configuration.totalBudget = try source.layeredBudget().totalBudget
    let context = ReportGenerationContext(service: service,
        snapshot: .init(day: source.day, sessions: source.sessions, redactionFailed: false), settings: source.settings, history: [])
    guard case .batched(let plan) = try await ReportGenerationPlan.build(context, credential: key,
        tokenizer: OfflineReportTokenizer(), redact: { $0 }) else { throw LiveOpenAIError.unexpectedConfiguration }
    let access = LiveOpenAIAccess(requestLimit: 4)
    print("LIVE COMPONENT generation HTTP=4; 19 facts versus two blockers, each twice; no automatic retries")
    for progress in [true, false] {
        var facts: [ReportFactPayload.Fact] = []
        if progress {
            facts.append(.init(references: [7], turns: ["1/1"], status: .confirmed, summary: try #require(source.turns.first?.finalAnswer)))
            for (index, session) in source.sessions.dropFirst().enumerated() {
                let names = try session.turns.map { turn in
                    try #require(turn.finalAnswer).components(separatedBy: ";")[0]
                        .replacingOccurrences(of: "Drafted the configuration rule for ", with: "")
                }
                facts.append(.init(references: [7], turns: (1...4).map { "\(index + 2)/\($0)" }, status: .unconfirmed,
                    summary: "Drafted distinct configuration rules for " + names.joined(separator: ", ") + "; review is pending and none has been released."))
            }
        }
        facts += [.init(references: [7], turns: ["9/4"], status: .unconfirmed,
            summary: "The shared synthetic schema mismatch blocks integrating these rules; affected scope unspecified."),
            .init(references: [7], turns: ["17/4"], status: .unconfirmed,
            summary: "The synthetic sign-off is still missing; release remains blocked; affected scope unspecified.")]
        let block = try ReportJSON.encode(ReportFactNode.Input(id: 7, facts: facts, noRelevantContent: false,
            completeTurns: Array(Set(facts.flatMap(\.turns))).sorted()))
        for repetition in 1...2 {
            let payload = try await recordedComponentRequest(.init(intent: .composeReport, configuration: service.configuration,
                credential: key, instruction: plan.prepared.batchFinalInstruction, input: plan.input(upstream: [7]),
                schema: plan.finalSchema, streaming: service.validation.streaming == .supported, additionalInputs: [block]),
                access: access, output: root.appendingPathComponent("composition-component.json"))
            let report = try ReportPayload.render(payload, language: source.settings.outputLanguage)
            try Data(report.utf8).write(to: root.appendingPathComponent("composition-\(progress ? "progress" : "blockers")-\(repetition).md"))
            print("LIVE COMPONENT progress=\(progress) repetition=\(repetition) crossed=\(hasCrossedS08BlockerCause(report)) full-risk-inventory=\(hasFullS08RiskInventory(report))")
            #expect(!hasCrossedS08BlockerCause(report) && !hasFullS08RiskInventory(report))
            expectS08CompletionSignals(report)
            expectS08SignOffSignals(report)
            expectS08ScopeSignals(report, explicitlyLocal: false)
        }
    }
}

@MainActor
private func recordedComponentRequest(_ request: AIRequest, access: LiveOpenAIAccess, output: URL) async throws -> String {
    let response: Result<String, any Error>
    do { response = .success(try await access.execute(request)) }
    catch { response = .failure(error) }
    try JSONEncoder().encode(["requests": await access.records]).write(to: output)
    return try response.get()
}

private func expectS08CompletionSignals(_ report: String) {
    let overview = report.lowercased().components(separatedBy: "## today’s overview\n\n").last?
        .components(separatedBy: "\n\n## completed work").first ?? ""
    let widened = overview.range(of: #"settings work (?:is |was |has been )?complete(?:d)?\b|(?:two|both|2) (?:same-day )?work items (?:were |are )?completed"#,
        options: .regularExpression) != nil
    #expect(!widened)
    let body = report.lowercased()
    let downgraded = ["document was drafted", "drafted the document", "document remains a draft", "document draft"]
    #expect(downgraded.allSatisfy { !body.contains($0) })
    #expect(overview.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count <= 3)
}

private func hasNarrowedSignOffScope(_ texts: [String]) -> Bool {
    texts.contains { text in
        let body = text.lowercased()
        let explicit = ["release remains blocked for synth36-08-b16", "release is blocked for synth36-08-b16",
            "sign-off for synth36-08-b16", "sign-off is still missing for synth36-08-b16",
            "b16-4 remains blocked", "b16-4 release", "b16-4's release"]
        if explicit.contains(where: body.contains) { return true }
        return body.components(separatedBy: ". ").contains { sentence in
            sentence.contains("sign-off") && sentence.contains("b16")
                && !sentence.contains("draft") && !sentence.contains("review")
        }
    }
}

private func expectS08SignOffSignals(_ report: String, explicitlyLocal: Bool = false) {
    let lines = report.lowercased().components(separatedBy: "\n").filter { $0.contains("sign-off") }
    #expect(!lines.isEmpty)
    if explicitlyLocal {
        #expect(lines.contains { $0.contains("only") && $0.contains("b16-4") })
    } else {
        let preserved = !hasNarrowedSignOffScope(lines)
        #expect(preserved)
    }
}

// Fixed v1 phrases only; passing these signals never replaces review of every section.
private func expectS08ScopeSignals(_ report: String, explicitlyLocal: Bool) {
    let body = report.lowercased()
    let risks = body.components(separatedBy: "## issues & risks\n\n").last?
        .components(separatedBy: "\n\n## tomorrow’s plan").first ?? ""
    #expect(risks.contains("schema") && risks.contains("integrat") && risks.contains("sign-off"))
    if explicitlyLocal {
        #expect(risks.contains("only") && risks.contains("synth36-08-b08-4") && risks.contains("other rules"))
    } else {
        let narrowed = ["integrating synth36-08-b08", "integration for synth36-08-b08",
            "these rules for synth36-08-b08", "b08 rules", "b08-4 rule", "b08-4-related rules",
            "b08-4 integration path"]
        let blockerLines = body.components(separatedBy: "\n").filter {
            $0.contains("schema") || $0.contains("integrat") || $0.contains("block")
        }.joined(separator: "\n")
        #expect(narrowed.allSatisfy { !blockerLines.contains($0) })
        #expect(risks.components(separatedBy: "\n").filter { $0.contains("schema") }.allSatisfy { !$0.contains("all rules") })
    }
}

private struct LivePlan: Codable {
    let id: String
    let totalBudget: Int
    let outputLimit: Int
    let inputLimit: Int
    let sessions: Int
    let turns: Int
    let userBytes: Int
    let answerBytes: Int
    let path: String
    let minimumRequests: Int
    let maximumRequests: Int
    let extractionRequests: Int
    let maximumMergeLayers: Int
    let fragments: Int
    let splitTurns: Int
    let auxiliaryClippedDuringExtraction: Bool

    @MainActor static func make(_ scenario: ReportAcceptanceScenario, service: SavedAIService, credential: String) async throws -> Self {
        var saved = service; saved.configuration.totalBudget = scenario.totalBudget
        let days = Set((1...max(1, scenario.settings.historyLookbackDays)).prefix(scenario.settings.historyLookbackDays).map {
            scenario.day.calendar.date(byAdding: .day, value: -$0, to: scenario.day.start)!
        })
        let context = ReportGenerationContext(service: saved,
            snapshot: .init(day: scenario.day, sessions: scenario.sessions, redactionFailed: false), settings: scenario.settings,
            history: scenario.history.filter { days.contains($0.day.start) }.sorted { $0.day.calendarDate > $1.day.calendarDate })
        let plan = try await ReportGenerationPlan.build(context, credential: credential, tokenizer: OfflineReportTokenizer(), redact: { $0 })
        let fragments: [ReportInputFragment]
        let clipped: Bool, path: String
        switch plan {
        case .direct: fragments = []; clipped = false; path = "direct"
        case .batched(let batch):
            fragments = batch.extraction.flatMap(\.fragments)
            clipped = batch.extraction.contains(where: \.auxiliaryClipped); path = "batched"
        }
        let difference = scenario.totalBudget - saved.configuration.outputLimit
        return .init(id: "\(saved.configuration.service.rawValue)-\(scenario.id)", totalBudget: scenario.totalBudget,
            outputLimit: saved.configuration.outputLimit, inputLimit: difference / 5 * 4 + difference % 5 * 4 / 5,
            sessions: scenario.sessions.count, turns: scenario.turns.count, userBytes: scenario.userBytes, answerBytes: scenario.answerBytes,
            path: path, minimumRequests: plan.scale.minimumRequests, maximumRequests: plan.scale.maximumRequests,
            extractionRequests: plan.scale.extractionRequests, maximumMergeLayers: plan.scale.mergeLayers,
            fragments: fragments.count, splitTurns: Set(fragments.filter { $0.parts > 1 }.map(\.association)).count,
            auxiliaryClippedDuringExtraction: clipped)
    }
}

private struct LiveTaskRecord: Codable {
    let id: String
    let plan: LivePlan
    let seconds: Double
    let error: String?
    let result: String
    let actualPath: String
    let actualMergeLayers: Int
    let historyDays: [String]
    let requests: [LiveOpenAIAccess.Record]
}

private enum LiveOpenAITarget {
    static let model = "gpt-6-luna"
}

func liveOpenAIConfiguration(_ service: AIServiceType) -> AIServiceConfiguration {
    var configuration = AIServiceConfiguration(service: service)
    configuration.endpoint = service.endpointExample
    configuration.model = LiveOpenAITarget.model
    configuration.outputLimit = 3_000
    switch service {
    case .chatCompletions: configuration.defaults = .chatCompletions(.init(reasoningEffort: AIReasoningEffort.none))
    case .responses: configuration.defaults = .responses(.init(reasoningEffort: AIReasoningEffort.none))
    case .messages: break
    }
    return configuration
}

private actor LiveOpenAIAccess: AIServiceAccess {
    struct Record: Codable, Sendable {
        let intent: String
        let inputTokens: Int
        let inputLimit: Int
        let outputTokens: Int?
        let visibleBudget: Int?
        let backgroundUnits: Int
        let historyUnits: Int
        let fragments: Int
        let userBytes: Int
        let answerBytes: Int
        let seconds: Double
        let error: String?
    }
    private let client = AIServiceClient(transport: .production())
    private let requestLimit: Int
    private let extractionOnly: Bool
    private var dispatched = 0
    private(set) var records: [Record] = []
    init(requestLimit: Int, extractionOnly: Bool = false) {
        self.requestLimit = requestLimit; self.extractionOnly = extractionOnly
    }

    func execute(_ request: AIRequest) async throws -> String {
        if extractionOnly {
            guard case .extractFacts = request.intent else { throw LiveOpenAIError.extractionComplete }
        }
        let configuration = request.configuration
        guard [.chatCompletions, .responses].contains(configuration.service),
              configuration.endpoint == configuration.service.endpointExample,
              configuration.model == LiveOpenAITarget.model, dispatched < requestLimit else { throw LiveOpenAIError.unexpectedConfiguration }
        dispatched += 1
        let intent: String
        switch request.intent {
        case .probe(let stage): intent = "probe-\(stage.rawValue)"
        case .extractFacts: intent = "extract"
        case .mergeFacts: intent = "merge"
        case .composeReport: intent = "compose"
        }
        let budget = try await ReportRequestBudget.make(instruction: request.instruction, schema: request.schema,
            configuration: configuration, tokenizer: OfflineReportTokenizer())
        let tokens = try await budget.count(request.input, blocks: request.additionalInputs)
        guard tokens <= budget.limit else { throw AIRequestError.budget }
        let input = (try? JSONSerialization.jsonObject(with: Data(request.input.utf8))) as? [String: Any]
        let background = (input?["background"] as? [Any])?.count ?? 0
        let history = (input?["historicalReports"] as? [Any])?.count ?? 0
        let visibleBudget = input?["visibleBudget"] as? Int
        let fragments = (input?["fragments"] as? [[String: Any]]) ?? []
        let turns = fragments.isEmpty ? (input?["today"] as? [[String: Any]]) ?? [] : fragments
        let userBytes = turns.reduce(0) { $0 + (($1["user"] as? String)?.utf8.count ?? 0) }
        let answerBytes = turns.reduce(0) { $0 + (($1["finalAnswer"] as? String)?.utf8.count ?? 0) }
        let start = Date()
        do {
            let result = try await client.execute(request)
            let outputTokens = try await OfflineReportTokenizer().count(result)
            records.append(.init(intent: intent, inputTokens: tokens, inputLimit: budget.limit,
                outputTokens: outputTokens, visibleBudget: visibleBudget,
                backgroundUnits: background, historyUnits: history, fragments: fragments.count, userBytes: userBytes, answerBytes: answerBytes,
                seconds: Date().timeIntervalSince(start), error: nil))
            return result
        } catch {
            records.append(.init(intent: intent, inputTokens: tokens, inputLimit: budget.limit,
                outputTokens: nil, visibleBudget: visibleBudget,
                backgroundUnits: background, historyUnits: history, fragments: fragments.count, userBytes: userBytes, answerBytes: answerBytes,
                seconds: Date().timeIntervalSince(start), error: AIRequestError.reason(for: error).rawValue))
            throw error
        }
    }
}
