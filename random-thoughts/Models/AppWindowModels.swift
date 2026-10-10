import Foundation

enum AppWindowKind: Sendable {
    case report
    case settings
}

enum AppWindowMode: String, Sendable {
    case foreground = "foreground"
    case menuBar = "menu_bar"
}

enum AppLaunchReason: Sendable {
    case user
    case login
}

enum AppWindowEffect: Equatable, Sendable {
    case applyMode(AppWindowMode)
    case present(AppWindowKind, session: UUID)
    case hide
    case minimizeReport
    case closeKeyWindow
    case quit
}
