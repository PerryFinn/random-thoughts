import AppKit
import Foundation
import SwiftUI
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportLayoutTests {
    @Test func reportFitsDefaultAndMinimumSizesWithoutAWindow() {
        let flow = DailyReportFlow(
            now: { Date(timeIntervalSince1970: 1_000) },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            performWindowEffect: { _ in },
            recordWindowMode: { _ in }
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
