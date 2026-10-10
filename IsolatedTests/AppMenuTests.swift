import AppKit
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct AppMenuTests {
    @Test func menuOffersSpecifiedShortcutsAndOnlyMinimizesTheReport() throws {
        let flow = DailyReportFlow(
            storage: ControlledReportStorage(),
            now: { Date(timeIntervalSince1970: 1_000) },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            performWindowEffect: { _ in },
            recordWindowMode: { _ in },
            copyMarkdown: { _ in }
        )
        var keyWindow: AppWindowKind? = .settings
        let commands = AppMenuCommands(flow: flow, keyWindowKind: { keyWindow })
        let menu = commands.makeMainMenu()
        let items = menu.items.flatMap { $0.submenu?.items ?? [] }
        for key in ["1", ",", "w", "m", "q"] {
            let item = try #require(items.first { $0.keyEquivalent == key })
            #expect(item.keyEquivalentModifierMask == .command)
            #expect(item.target === commands)
        }
        #expect(!items.contains { $0.keyEquivalent == "n" })
        let minimize = try #require(items.first { $0.keyEquivalent == "m" })
        let close = try #require(items.first { $0.keyEquivalent == "w" })
        #expect(!commands.validateMenuItem(minimize))
        #expect(commands.validateMenuItem(close))

        keyWindow = .report
        #expect(commands.validateMenuItem(minimize))
        keyWindow = nil
        #expect(!commands.validateMenuItem(minimize))
        #expect(!commands.validateMenuItem(close))
    }
}
