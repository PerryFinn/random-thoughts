import SwiftUI

struct DailyReportView: View {
    let flow: DailyReportFlow

    var body: some View {
        NavigationSplitView(columnVisibility: historyVisibility) {
            VStack(alignment: .leading, spacing: 16) {
                Text("日报历史")
                    .font(.headline)
                Text("已保存的工作日报将在这里显示。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                dateNavigation
                Divider()
                ContentUnavailableView {
                    Label("工作日报", systemImage: "doc.text")
                } description: {
                    Text("选择单个报告日整理工作。会话来源、手写、生成与保存将在后续开放。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: AppWindowConfiguration.report.minimumSize.width,
            idealWidth: AppWindowConfiguration.report.defaultSize.width,
            maxWidth: .infinity,
            minHeight: AppWindowConfiguration.report.minimumSize.height,
            idealHeight: AppWindowConfiguration.report.defaultSize.height,
            maxHeight: .infinity
        )
    }

    private var dateNavigation: some View {
        HStack(spacing: 12) {
            Button {
                flow.send(.toggleHistory)
            } label: {
                Label("日报历史", systemImage: "sidebar.left")
            }
            .pointerStyle(.link)

            Spacer()

            Button {
                flow.send(.moveDate(-1))
            } label: {
                Label("前一天", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .pointerStyle(.link)

            DatePicker("报告日", selection: Binding(
                get: { flow.selectedDate },
                set: { flow.send(.selectDate($0)) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .environment(\.timeZone, flow.reportTimeZone)
            .fixedSize()
            .pointerStyle(.link)

            Button {
                flow.send(.moveDate(1))
            } label: {
                Label("后一天", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .pointerStyle(.link)

            Spacer()

            Text(flow.reportTimeZone.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("当前报告时区")
        }
        .padding(16)
    }

    private var historyVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { flow.isHistoryVisible ? .all : .detailOnly },
            set: { visibility in
                if (visibility != .detailOnly) != flow.isHistoryVisible {
                    flow.send(.toggleHistory)
                }
            }
        )
    }
}
