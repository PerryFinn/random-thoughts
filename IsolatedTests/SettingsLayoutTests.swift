import AppKit
import SwiftUI
import Testing
@testable import random_thoughts

@MainActor
struct SettingsLayoutTests {
    @Test(arguments: SettingsRoute.allCases)
    func settingsFitsWithoutCreatingAWindow(route: SettingsRoute) {
        let selection = SettingsView.Selection()
        selection.route = route
        let hostingView = NSHostingView(rootView: SettingsView(
            selection: selection,
            intelligenceContent: AnyView(Text("合成模型监控")),
            proximityContent: AnyView(Text("合成蓝牙设置"))
        ))

        #expect(hostingView.fittingSize == NSSize(width: 860, height: 620))
        #expect(hostingView.window == nil)
    }
}
