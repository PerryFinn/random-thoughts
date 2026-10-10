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
                Text("需要保留的内容请返回编辑，逐份明确保存。放弃后这些草稿不会恢复。")
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(confirmation.draftDays) { day in Text("\(day.calendarDate) · \(day.timeZoneIdentifier)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button("返回编辑") { flow.send(.cancelConfirmation) }.keyboardShortcut(.defaultAction).pointerStyle(.link)
                Button(confirmLabel) { flow.send(.confirm(confirmation.id)) }.pointerStyle(.link)
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
        }
    }
    private var confirmLabel: String {
        switch confirmation.kind {
        case .overwrite: "确认覆盖保存"
        case .discard: "放弃草稿"
        case .close: "放弃并关闭"
        case .quit: "放弃并退出"
        }
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
