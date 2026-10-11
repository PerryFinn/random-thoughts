import AppKit
import SwiftUI

struct ReportConfirmationView: View {
    let flow: DailyReportFlow
    let confirmation: ReportConfirmation
    @State private var showsContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2)
            if case .overwrite = confirmation.kind {
                let diff = MarkdownDiff(previous: confirmation.previousMarkdown ?? "", proposed: confirmation.markdown ?? "")
                Text(diff.lines.isEmpty ? "正文无变化；确认后仍会更新保存时间。" : "核对原始 Markdown 后保存；正文变化时须重新确认。")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("展开未变化行", isOn: $showsContext).pointerStyle(.link)
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(diff.lines.isEmpty ? "正文无变化" : diff.unifiedText.components(separatedBy: "\n").prefix(3).joined(separator: "\n"))
                            .padding(.bottom, 8)
                        ForEach(diff.lines.filter { showsContext || $0.kind != .context }) { line in
                            Text((line.kind == .deletion ? "-" : line.kind == .insertion ? "+" : " ") + line.text)
                                .foregroundStyle(line.kind == .deletion ? .red : line.kind == .insertion ? .green : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !line.hasNewline { Text("\\ No newline at end of file").foregroundStyle(.secondary) }
                        }
                    }
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(12)
                }
                .background(.quaternary.opacity(0.25))
            } else {
                Text(explanation)
                    .foregroundStyle(.secondary)
                if confirmation.windowKind == .settings {
                    Text("生效时区：\(confirmation.oldTimeZoneIdentifier ?? "无效（原值保留）") → \(confirmation.newTimeZoneIdentifier ?? "无效，请返回修正")")
                        .font(.callout).textSelection(.enabled)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(confirmation.draftDays) { day in Text("\(day.calendarDate) · \(day.timeZoneIdentifier)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button(confirmation.windowKind == .settings ? "取消" : "返回编辑") { flow.send(.cancelConfirmation) }
                    .keyboardShortcut(.defaultAction).disabled(flow.isSaving)
                    .pointerStyle(flow.isSaving ? .default : .link)
                if canDiscardSettings {
                    Button(discardSettingsLabel) { flow.send(.discardSettingsAndContinue(confirmation.id)) }
                        .disabled(flow.isSaving).pointerStyle(flow.isSaving ? .default : .link)
                }
                Button(confirmLabel) { flow.send(.confirm(confirmation.id)) }
                    .disabled(flow.isSaving || confirmation.settings?.validationError != nil)
                    .pointerStyle(flow.isSaving || confirmation.settings?.validationError != nil ? .default : .link)
            }
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 760, maxWidth: .infinity, minHeight: 300, idealHeight: 540, maxHeight: .infinity)
        .background(ReportSheetSizing())
        .onExitCommand { flow.send(.cancelConfirmation) }
    }

    private var title: String {
        switch confirmation.kind {
        case .overwrite: "覆盖保存工作日报"
        case .discard: "放弃当前草稿"
        case .close: "关闭前检查全部草稿（\(confirmation.draftDays.count) 份）"
        case .quit: "退出前检查全部草稿（\(confirmation.draftDays.count) 份）"
        case .settings(.quit): "退出前检查设置和全部草稿（\(confirmation.draftDays.count) 份）"
        case .settings(.stay): "保存更改并删除 \(confirmation.draftDays.count) 份草稿"
        case .settings: "离开前检查未保存设置"
        }
    }
    private var confirmLabel: String {
        switch confirmation.kind {
        case .overwrite: "确认覆盖保存"
        case .discard: "放弃草稿"
        case .close: "放弃并关闭"
        case .quit: "放弃并退出"
        case .settings(.quit): "保存设置并放弃草稿退出"
        case .settings:
            confirmation.draftDays.isEmpty ? "保存更改并继续" : "保存更改并删除 \(confirmation.draftDays.count) 份草稿"
        }
    }

    private var explanation: String {
        switch confirmation.kind {
        case .settings(.quit):
            "保存设置或放弃设置后都会退出，并放弃以下全部日报草稿。需保留的日报请取消后逐份保存；取消不提交任何设置。"
        case .settings:
            "保存常规设置后才切换时区并删除以下旧时区 \(confirmation.draftDays.count) 份草稿；保留目标时区、其他时区草稿和全部已保存日报。放弃设置编辑不删除日报草稿，取消不提交。"
        default:
            "需要保留的内容请返回编辑，逐份明确保存。放弃后这些草稿不会恢复。"
        }
    }

    private var canDiscardSettings: Bool {
        guard case .settings(let continuation) = confirmation.kind else { return false }
        if case .stay = continuation { return false }
        return true
    }

    private var discardSettingsLabel: String {
        if case .settings(.quit) = confirmation.kind { "放弃设置与草稿并退出" } else { "放弃更改并继续" }
    }
}

private struct ReportSheetSizing: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) { }
    final class SizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: 600, height: 300)
        }
    }
}
