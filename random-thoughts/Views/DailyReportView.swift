import SwiftUI

struct DailyReportView: View {
    let flow: DailyReportFlow
    @FocusState private var editorIsFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: historyVisibility) {
            history.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                dateNavigation
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        editorToolbar
                        if let error = flow.storageError {
                            Text(error.message)
                                .font(.callout).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20).padding(.bottom, 8)
                        }
                        if flow.confirmedSnapshot?.redactionFailed == true {
                            Text("凭据遮盖未能全部完成；快照仍可使用，但可能保留秘密。")
                                .font(.callout).foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                        }
                        if flow.sourceSelectionNeedsConfirmation {
                            Text("来源已变化；既有快照保留，新选择须重新确认。")
                                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                        }
                        DailyReportGenerationStatusView(flow: flow)
                        content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if flow.isSourceDrawerVisible {
                        Divider()
                        DailyReportSourcesView(flow: flow).frame(width: 300)
                    }
                }
                Divider()
                footer
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
        .sheet(item: Binding(get: {
            flow.confirmation?.windowKind == .report ? flow.confirmation : nil
        }, set: {
            if $0 == nil, flow.confirmation?.windowKind == .report { flow.send(.cancelConfirmation) }
        })) { confirmation in
            ReportConfirmationView(flow: flow, confirmation: confirmation)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日报历史").font(.headline)
            if flow.historyDays.isEmpty {
                Text("保存后可在这里重新查看。草稿仅在本次窗口内保留。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(flow.historyDays) { day in
                        Button { flow.send(.selectReportDay(day)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.calendarDate).font(.headline)
                                Text(day.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary)
                                if flow.draftDays.contains(day) {
                                    Label("草稿 · 尚未保存", systemImage: "circle.fill").font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(day == flow.selectedDay ? Color.accentColor.opacity(0.12) : .clear)
                            .clipShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).pointerStyle(.link)
                    }
                }
            }
        }
        .padding(20)
    }

    private var editorToolbar: some View {
        HStack {
            Picker("正文模式", selection: Binding(get: { flow.isPreview }, set: { flow.send(.setPreview($0)) })) {
                Text("编辑").tag(false)
                Text("预览").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 150).pointerStyle(.link)
            Spacer()
            Text(flow.hasDraft ? "草稿 · 尚未保存" : flow.savedReports[flow.selectedDay] == nil ? "尚未创建" : "已保存")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        if !flow.isStorageReady {
            ContentUnavailableView("日报存储", systemImage: "externaldrive", description: Text(
                flow.storageError == nil ? "正在打开本机日报数据库…" : "存储尚不可用，原数据已保留。修复后可重新打开日报窗口。"
            ))
        } else if !flow.canEditSelectedReport {
            ContentUnavailableView {
                Label("报告时区无效", systemImage: "globe")
            } description: {
                Text("原固定时区已保留。请先修正常规设置；已有日报仍可从历史查看和编辑。")
            } actions: {
                Button("打开常规设置") {
                    flow.send(.open(.settings))
                    flow.send(.requestSettingsPage(.general))
                }
                .pointerStyle(.link)
            }
        } else if flow.isPreview {
            ScrollView {
                Text(SafeMarkdown.render(flow.body)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
        } else {
            ZStack(alignment: .topLeading) {
                let day = flow.selectedDay
                let session = flow.openWindows[.report]
                let revision = flow.reportEditRevision
                TextEditor(text: Binding(get: { flow.body }, set: {
                    if let session { flow.send(.editBody($0, day: day, session: session, revision: revision)) }
                }))
                .font(.system(.body, design: .monospaced)).focused($editorIsFocused)
                .disabled(flow.isSaving || flow.isGeneratingSelectedReport).id(day)
                if flow.body.isEmpty, !flow.hasDraft, flow.savedReports[day] == nil, !editorIsFocused {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("开始手写工作日报") { editorIsFocused = true }
                            .disabled(flow.isSaving || flow.isGeneratingSelectedReport)
                            .pointerStyle(flow.isSaving || flow.isGeneratingSelectedReport ? .default : .link)
                        Button("打开来源会话") { flow.send(.showSources) }.pointerStyle(.link)
                    }
                    .padding(10)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("复制 Markdown") { flow.send(.copyMarkdown) }
                .disabled(!flow.isStorageReady).pointerStyle(flow.isStorageReady ? .link : .default)
            Button("放弃草稿") { flow.send(.requestDiscardDraft) }
                .disabled(!flow.hasDraft || flow.isSaving || flow.isGeneratingSelectedReport)
                .pointerStyle(flow.hasDraft && !flow.isSaving && !flow.isGeneratingSelectedReport ? .link : .default)
            if flow.generationRetryAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in generateButton }
            } else { generateButton }
            if let notice = flow.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if flow.isSaving { ProgressView().controlSize(.small) }
            Button(flow.isSaving ? "正在保存…" : "保存") { flow.send(.save) }
                .buttonStyle(.borderedProminent).disabled(!flow.isStorageReady || !flow.canEditSelectedReport || flow.isSaving || flow.isGeneratingSelectedReport)
                .pointerStyle(flow.isStorageReady && flow.canEditSelectedReport && !flow.isSaving && !flow.isGeneratingSelectedReport ? .link : .default)
        }
        .padding(16)
    }

    private var generateButton: some View {
        Button(flow.hasDraft ? "重新生成" : "生成日报") { flow.send(.generateReport) }
            .disabled(!flow.canGenerateReport).pointerStyle(flow.canGenerateReport ? .link : .default)
    }

    private var dateNavigation: some View {
        HStack(spacing: 12) {
            Button { flow.send(.toggleHistory) } label: { Label("日报历史", systemImage: "sidebar.left") }
                .pointerStyle(.link)
            Spacer()
            Button { flow.send(.moveDate(-1)) } label: {
                Label("前一天", systemImage: "chevron.left").labelStyle(.iconOnly)
            }
            .pointerStyle(.link)
            DatePicker("报告日", selection: Binding(get: { flow.selectedDate }, set: { flow.send(.selectDate($0)) }), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field).environment(\.timeZone, flow.reportTimeZone)
                .fixedSize().pointerStyle(.link)
            Button { flow.send(.moveDate(1)) } label: {
                Label("后一天", systemImage: "chevron.right").labelStyle(.iconOnly)
            }
            .pointerStyle(.link)
            Spacer()
            Button("来源（\(flow.selectedSessionIDs.count)）") {
                flow.send(flow.isSourceDrawerVisible ? .hideSources : .showSources)
            }
            .pointerStyle(.link)
            Text(flow.effectiveTimeZoneIdentifier ?? "报告时区无效，请在设置中修正")
                .font(.caption).foregroundStyle(flow.effectiveTimeZoneIdentifier == nil ? .red : .secondary)
                .lineLimit(1).help("当前生效报告时区；历史记录保留其原有时区")
        }
        .padding(16)
    }

    private var historyVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { flow.isHistoryVisible ? .all : .detailOnly }, set: {
            if ($0 != .detailOnly) != flow.isHistoryVisible { flow.send(.toggleHistory) }
        })
    }
}
