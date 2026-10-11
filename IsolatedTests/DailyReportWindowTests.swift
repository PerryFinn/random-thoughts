import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportWindowTests {
    @Test func oldCloseCallbackCannotCloseAReopenedReport() throws {
        let environment = WindowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.launch(.user))
        let old = try #require(flow.openWindows[.report])
        flow.send(.windowClosed(.report, session: old))
        flow.send(.open(.report))
        let reopened = try #require(flow.openWindows[.report])

        flow.send(.windowClosed(.report, session: old))
        #expect(reopened != old)
        #expect(flow.openWindows[.report] == reopened)
        #expect(flow.windowMode == .foreground)
    }

    @Test func reportDateNavigationAndHistoryResetOnlyOnActualReopening() throws {
        let environment = WindowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.launch(.user))
        let report = try #require(flow.openWindows[.report])
        #expect(flow.selectedDate == Date(timeIntervalSince1970: 0))

        flow.send(.moveDate(1))
        #expect(flow.selectedDate == Date(timeIntervalSince1970: 86_400))
        flow.send(.selectDate(Date(timeIntervalSince1970: 172_900)))
        flow.send(.toggleHistory)
        flow.send(.hide)
        flow.send(.minimizeReport)
        flow.send(.open(.report))
        #expect(flow.selectedDate == Date(timeIntervalSince1970: 172_800))
        #expect(!flow.isHistoryVisible)

        flow.send(.windowClosed(.report, session: report))
        flow.send(.open(.report))
        #expect(flow.selectedDate == Date(timeIntervalSince1970: 0))
        #expect(flow.isHistoryVisible)
    }

    @Test func onlyActualClosingOfTheLastWindowReturnsToMenuBar() throws {
        let environment = WindowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.launch(.user))
        let report = try #require(flow.openWindows[.report])
        flow.send(.open(.settings))
        let settings = try #require(flow.openWindows[.settings])

        flow.send(.hide)
        flow.send(.minimizeReport)
        flow.send(.systemSleep)
        flow.send(.systemWake)
        #expect(flow.openWindows == [.report: report, .settings: settings])
        #expect(flow.windowMode == .foreground)
        #expect(environment.modes == [.foreground])

        flow.send(.windowClosed(.report, session: report))
        #expect(flow.windowMode == .foreground)
        #expect(flow.openWindows == [.settings: settings])

        flow.send(.windowClosed(.settings, session: settings))
        #expect(flow.windowMode == .menuBar)
        #expect(environment.modes == [.foreground, .menuBar])
        flow.send(.systemSleep)
        flow.send(.systemWake)
        #expect(environment.effects.suffix(2) == [.applyMode(.menuBar), .applyMode(.menuBar)])
        #expect(flow.openWindows.isEmpty)
    }

    @Test func repeatedOpeningAndReactivationReuseBothWindows() throws {
        let environment = WindowTestEnvironment()
        let flow = environment.makeFlow()
        flow.send(.launch(.login))
        flow.send(.open(.settings))
        let settings = try #require(flow.openWindows[.settings])
        flow.send(.open(.settings))
        #expect(flow.openWindows[.settings] == settings)
        #expect(flow.openWindows[.report] == nil)

        flow.send(.reactivate)
        let report = try #require(flow.openWindows[.report])
        flow.send(.open(.report))
        flow.send(.reactivate)

        #expect(flow.openWindows == [.report: report, .settings: settings])
        #expect(environment.effects.suffix(2) == [
            .present(.report, session: report), .present(.report, session: report)
        ])
        #expect(environment.modes == [.menuBar, .foreground])
    }

    @Test func userLaunchOpensReportWhileLoginLaunchKeepsMenuBar() {
        let user = WindowTestEnvironment()
        let userFlow = user.makeFlow()
        userFlow.send(.launch(.user))

        #expect(userFlow.windowMode == .foreground)
        #expect(userFlow.openWindows[.report] != nil)
        #expect(userFlow.openWindows[.settings] == nil)
        #expect(user.modes == [.foreground])

        let login = WindowTestEnvironment()
        let loginFlow = login.makeFlow()
        loginFlow.send(.launch(.login))

        #expect(loginFlow.windowMode == .menuBar)
        #expect(loginFlow.openWindows.isEmpty)
        #expect(login.effects == [.applyMode(.menuBar)])
        #expect(login.modes == [.menuBar])
    }
}

@MainActor
private final class WindowTestEnvironment {
    var effects: [AppWindowEffect] = []
    var modes: [AppWindowMode] = []

    func makeFlow() -> DailyReportFlow {
        DailyReportFlow(
            storage: ControlledReportStorage(),
            codexSourceAccess: ControlledCodexSource(),
            now: { Date(timeIntervalSince1970: 1_000) },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            performWindowEffect: { self.effects.append($0) },
            performContextEffect: { _ in },
            recordWindowMode: { self.modes.append($0) },
            recordCodexCheck: { _ in },
            copyMarkdown: { _ in }
        )
    }
}
