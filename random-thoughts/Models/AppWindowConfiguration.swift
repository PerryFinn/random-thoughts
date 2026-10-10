import Foundation

struct AppWindowConfiguration: Sendable {
    let defaultSize: CGSize
    let minimumSize: CGSize
    let canMinimize: Bool
    let canResize: Bool
    let canFullScreen: Bool

    static let report = Self(
        defaultSize: CGSize(width: 1100, height: 760),
        minimumSize: CGSize(width: 900, height: 620),
        canMinimize: true,
        canResize: true,
        canFullScreen: true
    )

    static let settings = Self(
        defaultSize: CGSize(width: 860, height: 620),
        minimumSize: CGSize(width: 860, height: 620),
        canMinimize: false,
        canResize: false,
        canFullScreen: false
    )
}
