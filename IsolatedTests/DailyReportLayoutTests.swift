import AppKit
import Foundation
import SwiftUI
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportLayoutTests {
    @Test func longEditorPreviewAndConfirmationFitWithoutAWindow() async throws {
        let environment = ReportFlowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.open(.report))
        await flow.waitForStorage()
        let session = try #require(flow.openWindows[.report])
        let raw = String(repeating: "# 合成标题\n\n长正文 👩🏽‍💻 [链接](https://example.invalid)\n", count: 200)
        flow.send(.editBody(raw, day: flow.selectedDay, session: session))
        for preview in [false, true] {
            flow.send(.setPreview(preview))
            let view = NSHostingView(rootView: DailyReportView(flow: flow).frame(width: 900, height: 620))
            #expect(view.fittingSize == NSSize(width: 900, height: 620))
            #expect(view.window == nil)
        }
        flow.send(.save)
        await flow.waitForStorage()
        flow.send(.editBody(raw + "追加\n", day: flow.selectedDay, session: session))
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
            now: { Date(timeIntervalSince1970: 1_000) },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            performWindowEffect: { _ in },
            recordWindowMode: { _ in },
            copyMarkdown: { _ in }
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

    @Test func settingsKeepFixedSizeForExistingAndDailyReportRoutes() {
        for route in SettingsRoute.allCases {
            let view = NSHostingView(rootView: SettingsView(
                intelligenceContent: AnyView(Text("合成模型监控")),
                proximityContent: AnyView(Text("合成蓝牙设置")),
                selection: route
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
