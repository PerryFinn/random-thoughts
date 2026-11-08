import AppKit
import Testing
@testable import random_thoughts

@MainActor
struct AppMenuTests {
    @Test func menuOffersSettingsAndQuitAndClosesOnlyTheKeySettingsWindow() throws {
        var didShowSettings = false
        var settingsIsKey = true
        let commands = AppMenuCommands(
            showSettings: { didShowSettings = true },
            isSettingsKeyWindow: { settingsIsKey }
        )
        let menu = commands.makeMainMenu()
        let application = try #require(menu.item(withTitle: "随想")?.submenu)
        let window = try #require(menu.item(withTitle: "窗口")?.submenu)
        #expect(application.items.map(\.keyEquivalent).filter { !$0.isEmpty }.sorted() == [",", "h", "h", "q"])
        #expect(window.items.map(\.keyEquivalent) == ["w"])

        let items = application.items + window.items
        for key in [",", "w", "q"] {
            let item = try #require(items.first { $0.keyEquivalent == key })
            #expect(item.keyEquivalentModifierMask == .command)
            #expect(item.target === commands)
        }
        let close = try #require(items.first { $0.keyEquivalent == "w" })
        #expect(commands.validateMenuItem(close))

        settingsIsKey = false
        #expect(!commands.validateMenuItem(close))

        let settingsIndex = try #require(application.items.firstIndex { $0.keyEquivalent == "," })
        // The hostless runner needs an AppKit application for menu action dispatch.
        _ = NSApplication.shared
        application.performActionForItem(at: settingsIndex)
        #expect(didShowSettings)
    }

    @Test func settingsOffersModelMonitoringAndBluetoothUnlock() {
        #expect(SettingsRoute.allCases == [.intelligence, .proximityUnlock])
        #expect(SettingsRoute.allCases.map(\.title) == ["模型监控", "蓝牙解锁"])
        #expect(SettingsView.Selection().route == .intelligence)
    }
}
