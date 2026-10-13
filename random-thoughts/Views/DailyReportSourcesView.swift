import SwiftUI

struct DailyReportSourcesView: View {
    let flow: DailyReportFlow
    @State private var showsGenerationSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("来源会话").font(.headline)
                Spacer()
                Button { flow.send(.hideSources) } label: {
                    Label("关闭来源抽屉", systemImage: "xmark").labelStyle(.iconOnly)
                }
                .buttonStyle(.plain).pointerStyle(.link)
            }
            Picker("来源范围", selection: $showsGenerationSources) {
                Text("当前选择").tag(false)
                Text("草稿生成来源").tag(true)
            }
            .pickerStyle(.segmented).pointerStyle(.link)
            if showsGenerationSources {
                if let sources = flow.generationSources {
                    Text("整份草稿生成时的实际输入，不证明具体章节、条目或后续编辑。当前选择变化不改此清单。")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sources.groups) { group in
                                Text(group.title).font(.headline)
                                ForEach(Array(group.titles.enumerated()), id: \.offset) { _, title in Text(title).textSelection(.enabled) }
                            }
                            if !sources.historyDays.isEmpty {
                                Divider()
                                Text("实际历史参考 · 仅作背景").font(.headline)
                                ForEach(sources.historyDays) { day in Text("\(day.calendarDate) · \(day.timeZoneIdentifier)") }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("当前草稿没有生成来源。手写内容及从已保存日报建立的草稿不带来源清单。")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                selection
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(flow.sessionScan == nil ? "扫描会话" : "刷新") { flow.send(.scanSessions) }
                    .disabled(!flow.canScanSessions).pointerStyle(flow.canScanSessions ? .link : .default)
                if flow.isScanningSessions {
                    ProgressView().controlSize(.small)
                    Button("取消") { flow.send(.cancelSessionScan) }.pointerStyle(.link)
                }
                Spacer()
                Button("设置数据源") {
                    flow.send(.open(.settings))
                    flow.send(.requestSettingsPage(.dataSource))
                }
                .pointerStyle(.link)
            }
            if flow.isScanningSessions {
                Text(flow.sessionScanActivity == .waitingForSource ? "等待同一数据源的其他扫描，最多 30 秒…" : "正在扫描当前与归档会话…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = flow.sessionScanError {
                Text(error.scanMessage).font(.callout).foregroundStyle(error == .cancelled ? Color.secondary : Color.red)
            }
            if let scan = flow.sessionScan {
                Text(scan.isPartial ? "部分会话扫描：仅可确认以下读取成功项。" : scan.sessions.isEmpty ? "完整扫描，没有该报告日的候选会话。仍可手写日报。" : "已完整扫描；按会话选择当天全部合规轮次。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("全选") { flow.send(.selectAllSessions(true)) }
                        .disabled(!canSelect).pointerStyle(canSelect ? .link : .default)
                    Button("全不选") { flow.send(.selectAllSessions(false)) }
                        .disabled(!canSelect).pointerStyle(canSelect ? .link : .default)
                }
            } else if !flow.isScanningSessions, flow.sessionScanError == nil {
                Text("主动扫描后选择来源；确认后新轮次须刷新并重新确认。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(flow.sessionGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(group.title, isOn: Binding(get: {
                                group.sessions.allSatisfy { flow.selectedSessionIDs.contains($0.id) }
                            }, set: { flow.send(.selectSessionGroup(group.directory, $0)) }))
                                .font(.headline).disabled(!canSelect).pointerStyle(canSelect ? .link : .default)
                            if let directory = group.directory {
                                Text(directory).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    .lineLimit(2).help(directory)
                            }
                            ForEach(group.sessions) { session in
                                Toggle(isOn: Binding(get: { flow.selectedSessionIDs.contains(session.id) }, set: {
                                    flow.send(.selectSession(session.id, $0))
                                })) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.title).lineLimit(2).help(session.title)
                                        let unconfirmed = session.turns.filter { !$0.isResultConfirmed }.count
                                        Text("\(session.turns.count) 个当天轮次 · \(unconfirmed) 个结果未确认\(session.origin == .unknown ? " · 未知来源" : "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(!canSelect).pointerStyle(canSelect ? .link : .default)
                            }
                        }
                    }
                    if let scan = flow.sessionScan, !scan.failures.isEmpty {
                        Text("读取失败（\(scan.failures.count)）").font(.headline)
                        ForEach(scan.failures) { failure in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(failure.title).lineLimit(2).help(failure.title)
                                Text("无法读取，未纳入本次选择。可主动刷新重试。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let snapshot = flow.confirmedSnapshot {
                        Divider()
                        Text("已确认输入：\(snapshot.sessions.count) 个会话").font(.headline)
                        Text(flow.sourceSelectionNeedsConfirmation ? "当前选择已变化。既有快照保留，重新确认后才替换。" : "快照已固定，查看或确认不会额外读取 Codex。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("会话快照仍是敏感工作数据；凭据遮盖不能保证清除全部秘密。")
                .font(.caption).foregroundStyle(.secondary)
            Button(flow.isConfirmingSessions ? "正在固定快照…" : "确认 \(flow.selectedSessionIDs.count) 个会话") {
                flow.send(.confirmSessionSelection)
            }
            .buttonStyle(.borderedProminent).disabled(!flow.canConfirmSessionSelection)
            .pointerStyle(flow.canConfirmSessionSelection ? .link : .default)
        }
    }

    private var canSelect: Bool { !flow.isScanningSessions && !flow.isConfirmingSessions }
}
