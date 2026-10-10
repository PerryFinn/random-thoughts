import SwiftUI

struct SettingsView: View {
    static let windowSize = AppWindowConfiguration.settings.defaultSize

    let intelligenceContent: AnyView
    let proximityContent: AnyView
    @State private var selection: SettingsRoute

    init(
        intelligenceContent: AnyView,
        proximityContent: AnyView,
        selection: SettingsRoute = .intelligence
    ) {
        self.intelligenceContent = intelligenceContent
        self.proximityContent = proximityContent
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsRoute.allCases, selection: $selection) { route in
                Label(route.title, systemImage: route.systemImage)
                    .contentShape(Rectangle())
                    .pointerStyle(.link)
                    .tag(route)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 220)
        } detail: {
            switch selection {
            case .intelligence:
                intelligenceContent
            case .proximityUnlock:
                proximityContent
            case .dailyReports:
                DailyReportSettingsView()
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}

enum SettingsRoute: String, CaseIterable, Identifiable {
    case intelligence
    case proximityUnlock
    case dailyReports

    var id: Self { self }

    var title: String {
        switch self {
        case .intelligence: "模型监控"
        case .proximityUnlock: "蓝牙解锁"
        case .dailyReports: "工作日报"
        }
    }

    var systemImage: String {
        switch self {
        case .intelligence: "brain.head.profile"
        case .proximityUnlock: "lock.open.display"
        case .dailyReports: "doc.text"
        }
    }
}

private struct DailyReportSettingsView: View {
    @State private var section: DailyReportSettingsSection = .general

    var body: some View {
        VStack(spacing: 20) {
            Picker("工作日报", selection: $section) {
                ForEach(DailyReportSettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .pointerStyle(.link)

            ScrollView {
                ContentUnavailableView {
                    Label(section.title, systemImage: section.systemImage)
                } description: {
                    Text(section.summary + "这些设置尚未开放。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }
}

private enum DailyReportSettingsSection: String, CaseIterable, Identifiable {
    case general
    case dataSource
    case aiServices
    case contentManagement

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "常规"
        case .dataSource: "数据源"
        case .aiServices: "AI 服务"
        case .contentManagement: "内容管理"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .dataSource: "folder"
        case .aiServices: "sparkles"
        case .contentManagement: "externaldrive"
        }
    }

    var summary: String {
        switch self {
        case .general: "管理报告时区、输出语言、生成偏好与历史日报回看。"
        case .dataSource: "选择并检查用于读取本机会话的 Codex 数据源。"
        case .aiServices: "分别配置、校验与选择工作日报使用的 AI 服务。"
        case .contentManagement: "管理已保存的工作日报与本次窗口内存内容。"
        }
    }
}
