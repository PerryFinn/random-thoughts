import Observation
import SwiftUI

struct SettingsView: View {
    static let windowSize = CGSize(width: 860, height: 620)

    @Observable
    final class Selection {
        var route: SettingsRoute = .intelligence
    }

    @Bindable var selection: Selection
    let intelligenceContent: AnyView
    let proximityContent: AnyView

    var body: some View {
        NavigationSplitView {
            List(SettingsRoute.allCases, selection: $selection.route) { route in
                Label(route.title, systemImage: route.systemImage)
                    .contentShape(Rectangle())
                    .pointerStyle(.link)
                    .tag(route)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 220)
        } detail: {
            switch selection.route {
            case .intelligence:
                intelligenceContent
            case .proximityUnlock:
                proximityContent
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}

enum SettingsRoute: CaseIterable, Hashable, Identifiable {
    case intelligence
    case proximityUnlock

    var id: Self { self }

    var title: String {
        switch self {
        case .intelligence: "模型监控"
        case .proximityUnlock: "蓝牙解锁"
        }
    }

    var systemImage: String {
        switch self {
        case .intelligence: "brain.head.profile"
        case .proximityUnlock: "lock.open.display"
        }
    }
}
