import AppKit
import Foundation
import SwiftUI
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportLayoutTests {
    @Test func allNativeAIEditorsAndCredentialConfirmationFitWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = try await prepareAISettings(environment)
        let session = try #require(flow.openWindows[.settings])
        for service in AIServiceType.allCases {
            flow.send(.selectAIServiceType(service))
            var edit = flow.aiServiceEdit
            edit.configuration.endpoint = "http://localhost:8080/" + String(repeating: "very-long-route/", count: 80)
            edit.configuration.model = String(repeating: "长模型👩🏽‍💻", count: 120)
            flow.send(.editAIService(edit, session: session, revision: flow.aiServiceEditRevision))
            let editor = NSHostingView(rootView: DailyReportAIServiceView(flow: flow).frame(width: 580, height: 520))
            #expect(editor.fittingSize == NSSize(width: 580, height: 520))
            #expect(editor.window == nil)
            let settings = NSHostingView(rootView: SettingsView(flow: flow,
                intelligenceContent: AnyView(Text("合成模型")), proximityContent: AnyView(Text("合成蓝牙"))))
            #expect(settings.fittingSize == NSSize(width: 860, height: 620))
            #expect(settings.window == nil)
            flow.send(.selectAIServiceType(service == .messages ? .responses : .messages))
            let sheet = NSHostingView(rootView: ReportConfirmationView(flow: flow, confirmation: try #require(flow.confirmation))
                .frame(width: 760, height: 540))
            #expect(sheet.fittingSize == NSSize(width: 760, height: 540))
            #expect(sheet.window == nil)
            flow.send(.cancelConfirmation)
            flow.send(.revertAIService)
        }
    }

    @Test func sourceDrawerAndLongSessionListsFitTheMinimumReportWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let sessions = (0..<40).map { syntheticCandidate("会话 \($0) " + String(repeating: "很长标题", count: 30),
                                                        directory: "/synthetic/project/worktree-\($0)") }
        let flow = try await prepareSessionFlow(environment, sessions: sessions)
        let drawer = NSHostingView(rootView: DailyReportSourcesView(flow: flow).frame(width: 300, height: 420))
        #expect(drawer.fittingSize == NSSize(width: 300, height: 420))
        #expect(drawer.window == nil)
        let report = NSHostingView(rootView: DailyReportView(flow: flow).frame(width: 900, height: 620))
        #expect(report.fittingSize == NSSize(width: 900, height: 620))
        #expect(report.window == nil)
        flow.send(.toggleHistory)
        report.layoutSubtreeIfNeeded()
        #expect(report.fittingSize == NSSize(width: 900, height: 620))
    }

    @Test func dataSourceEditorAndDiagnosticsFitTheFixedSettingsWindowWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.dataSource))
        flow.send(.editCodexSource(CodexDataSourceConfiguration(
            mode: .manual, executablePath: "/synthetic/" + String(repeating: "很长的入口/", count: 80),
            explicitDirectory: "/synthetic/" + String(repeating: "很长的目录/", count: 80)
        ), session: try #require(flow.openWindows[.settings])))
        let editor = NSHostingView(rootView: DailyReportCodexSourceView(flow: flow).frame(width: 580, height: 520))
        #expect(editor.fittingSize == NSSize(width: 580, height: 520))
        #expect(editor.window == nil)
        let settings = NSHostingView(rootView: SettingsView(
            flow: flow, intelligenceContent: AnyView(Text("合成模型")), proximityContent: AnyView(Text("合成蓝牙"))
        ))
        #expect(settings.fittingSize == NSSize(width: 860, height: 620))
        #expect(settings.window == nil)
    }

    @Test func generalSettingsAndMergedConfirmationFitWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        flow.send(.open(.settings))
        await flow.waitForStorage()
        flow.send(.requestSettingsPage(.general))
        flow.send(.editBody("布局影响", day: flow.selectedDay, session: try #require(flow.openWindows[.report]), revision: flow.reportEditRevision))
        var edited = flow.generalSettingsEdit
        edited.timeZoneMode = .fixed
        edited.fixedTimeZoneIdentifier = "Asia/Shanghai"
        edited.generationPreferences = String(repeating: "长偏好 👩🏽‍💻\n", count: 200)
        flow.send(.editGeneralSettings(edited, session: try #require(flow.openWindows[.settings])))
        let view = NSHostingView(rootView: SettingsView(
            flow: flow, intelligenceContent: AnyView(Text("合成模型")), proximityContent: AnyView(Text("合成蓝牙"))
        ))
        #expect(view.fittingSize == NSSize(width: 860, height: 620))
        #expect(view.window == nil)
        flow.send(.requestSettingsPage(.dataSource))
        let confirmation = try #require(flow.confirmation)
        let sheet = NSHostingView(rootView: ReportConfirmationView(flow: flow, confirmation: confirmation)
            .frame(width: 760, height: 540))
        #expect(sheet.fittingSize == NSSize(width: 760, height: 540))
        #expect(sheet.window == nil)
    }

    @Test func longEditorPreviewAndConfirmationFitWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let raw = String(repeating: "# 合成标题\n\n长正文 👩🏽‍💻 [链接](https://example.invalid)\n", count: 200)
        flow.send(.editBody(raw, day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        for preview in [false, true] {
            flow.send(.setPreview(preview))
            let view = NSHostingView(rootView: DailyReportView(flow: flow).frame(width: 900, height: 620))
            #expect(view.fittingSize == NSSize(width: 900, height: 620))
            #expect(view.window == nil)
        }
        flow.send(.save)
        await flow.waitForStorage()
        flow.send(.editBody(raw + "追加\n", day: flow.selectedDay, session: session, revision: flow.reportEditRevision))
        flow.send(.save)
        let confirmation = try #require(flow.confirmation)
        let sheet = NSHostingView(rootView: ReportConfirmationView(flow: flow, confirmation: confirmation)
            .frame(width: 760, height: 540))
        #expect(sheet.fittingSize == NSSize(width: 760, height: 540))
        #expect(sheet.window == nil)
    }

    @Test func reportFitsDefaultAndMinimumSizesWithoutAWindow() {
        let flow = DailyReportFlow(
            storage: ControlledReportStorage(),
            aiCredentials: AIServiceCredentialCipher(key: Data(repeating: 0x21, count: 32)),
            codexSourceAccess: ControlledCodexSource(),
            now: { Date(timeIntervalSince1970: 1_000) },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            performWindowEffect: { _ in },
            performContextEffect: { _ in },
            recordWindowMode: { _ in },
            recordCodexCheck: { _ in },
            recordSessionScan: { _ in },
            recordAIStorage: { _ in },
            redactCredentials: { $0 },
            copyText: { _ in }
        )
        let defaultView = NSHostingView(rootView: DailyReportView(flow: flow))
        #expect(defaultView.fittingSize == NSSize(width: 1100, height: 760))
        #expect(defaultView.window == nil)

        let minimumView = NSHostingView(rootView: DailyReportView(flow: flow)
            .frame(width: 900, height: 620))
        #expect(minimumView.fittingSize == NSSize(width: 900, height: 620))
        #expect(minimumView.window == nil)
        flow.send(.toggleHistory)
        minimumView.layoutSubtreeIfNeeded()
        #expect(minimumView.fittingSize == NSSize(width: 900, height: 620))
    }

    @Test func settingsKeepFixedSizeForExistingAndDailyReportRoutes() async {
        for route in SettingsRoute.allCases {
            let flow = ReportFlowTestEnvironment().makeFlow()
            flow.send(.open(.settings))
            await flow.waitForStorage()
            flow.send(.requestSettingsPage(route.page))
            let view = NSHostingView(rootView: SettingsView(
                flow: flow,
                intelligenceContent: AnyView(Text("合成模型监控")),
                proximityContent: AnyView(Text("合成蓝牙设置"))
            ))
            #expect(view.fittingSize == NSSize(width: 860, height: 620))
            #expect(view.window == nil)
        }
        #expect(AppWindowConfiguration.report.minimumSize == NSSize(width: 900, height: 620))
        #expect(AppWindowConfiguration.report.canMinimize)
        #expect(AppWindowConfiguration.report.canResize)
        #expect(AppWindowConfiguration.report.canFullScreen)
        #expect(AppWindowConfiguration.settings.minimumSize == NSSize(width: 860, height: 620))
        #expect(!AppWindowConfiguration.settings.canMinimize)
        #expect(!AppWindowConfiguration.settings.canResize)
        #expect(!AppWindowConfiguration.settings.canFullScreen)
    }
}
