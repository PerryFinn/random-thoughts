import SwiftUI
import UniformTypeIdentifiers

struct DailyReportCodexSourceView: View {
    let flow: DailyReportFlow
    @State private var choosingEntry = false
    @State private var isChoosingPath = false
    @State private var pickerSession: UUID?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case entry, directory }
    private var canEdit: Bool { flow.isStorageReady && !flow.isSaving }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !flow.isStorageReady {
                        Text(flow.storageError?.message ?? "正在打开本机日报设置…").foregroundStyle(.secondary)
                    }
                    GroupBox("Codex 可执行入口") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("选择方式", selection: Binding(get: { flow.codexSourceEdit.mode }, set: { mode in
                                update { $0.mode = mode; $0.executablePath = "" }
                            })) {
                                Text("自动发现").tag(CodexDiscoveryMode.automatic)
                                Text("手动选择").tag(CodexDiscoveryMode.manual)
                            }
                            .pickerStyle(.segmented).disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                            if flow.codexSourceEdit.mode == .manual {
                                TextField("Codex 可执行入口的绝对路径", text: binding(\.executablePath))
                                    .textFieldStyle(.roundedBorder).disabled(!canEdit).focused($focusedField, equals: .entry)
                            } else {
                                Text(flow.codexSourceEdit.executablePath.isEmpty ? "尚未选择入口，保存并检查时自动发现。" : flow.codexSourceEdit.executablePath)
                                    .font(.callout).textSelection(.enabled)
                                Text("自动选择首个可用入口并保留；失效后需主动重新发现或手选，不自动换来源。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("选择入口…") { choose(entry: true) }
                                    .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                                if flow.codexSourceEdit.mode == .automatic {
                                    Button("重新发现并检查") { flow.send(.rediscoverCodexSource) }
                                        .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                                }
                            }
                            if let error = flow.codexSourceError, error.isExecutableError {
                                Text(error.message).font(.callout).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox("Codex 数据目录") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("留空使用启动继承的目录或 Codex 默认主目录", text: binding(\.explicitDirectory))
                                .textFieldStyle(.roundedBorder).disabled(!canEdit).focused($focusedField, equals: .directory)
                            Button("选择目录…") { choose(entry: false) }
                                .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                            Text("显式目录优先；无效时保留选择，不读取其他目录。清空输入并保存可恢复自动目录。")
                                .font(.callout).foregroundStyle(.secondary)
                            if let error = flow.codexSourceError, error.isDirectoryError {
                                Text(error.message).font(.callout).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    diagnostics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if flow.isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("撤销更改") { flow.send(.revertCodexSource) }
                    .disabled(!canEdit || !flow.hasCodexSourceEdits)
                    .pointerStyle(canEdit && flow.hasCodexSourceEdits ? .link : .default)
                Button(flow.isSaving ? "正在保存…" : "保存并检查") { flow.send(.saveCodexSource) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s")
                    .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
            }
        }
        .fileImporter(isPresented: $isChoosingPath, allowedContentTypes: choosingEntry ? [.item] : [.folder]) { result in
            guard case .success(let url) = result, let pickerSession else { return }
            var configuration = flow.codexSourceEdit
            if choosingEntry { configuration.mode = .manual; configuration.executablePath = url.path }
            else { configuration.explicitDirectory = url.path }
            flow.send(.editCodexSource(configuration, session: pickerSession))
        }
        .onChange(of: flow.codexSourceError) { _, error in
            if let error, error.isDirectoryError { focusedField = .directory }
            else if let error, [.executableMissing, .invalidExecutable, .executablePermission].contains(error) { focusedField = .entry }
        }
    }

    private var diagnostics: some View {
        GroupBox("已保存来源与检查") {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前状态：\(flow.codexSourceStatus.title)").font(.headline)
                if flow.isCheckingCodexSource {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在检查当前来源…")
                        Button("取消检查") { flow.send(.cancelCodexCheck) }.pointerStyle(.link)
                    }
                }
                Text("入口：\(flow.codexSource.configuration.executablePath.isEmpty ? "尚未选择" : flow.codexSource.configuration.executablePath)")
                    .font(.callout).textSelection(.enabled)
                Text("数据目录：\(flow.codexSource.resolvedDirectory ?? "尚未解析")").font(.callout).textSelection(.enabled)
                if let time = flow.codexSource.lastSuccessfulCheck {
                    Text("上次成功：\(time.formatted(date: .numeric, time: .standard))").font(.callout)
                    Text("诊断版本：\(flow.codexSource.version?.description ?? "未能解析")").font(.callout)
                } else { Text("尚无成功检查记录。").font(.callout) }
                Text("历史成功和版本不代表当前可用；手写、编辑和查看日报始终可用。")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = flow.codexSourceError, !error.isDirectoryError, !error.isExecutableError {
                    Text(error.message).font(.callout).foregroundStyle(error == .cancelled ? Color.secondary : Color.red)
                }
                if flow.codexSourceStorageError != nil {
                    Text("来源设置或历史诊断保存失败；原有持久数据保留，编辑输入仍可重新保存。")
                        .font(.callout).foregroundStyle(.red)
                }
                if flow.hasCodexSourceEdits { Text("有未保存的数据源更改。").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private func choose(entry: Bool) {
        choosingEntry = entry
        pickerSession = flow.openWindows[.settings]
        isChoosingPath = true
    }

    private func binding(_ keyPath: WritableKeyPath<CodexDataSourceConfiguration, String>) -> Binding<String> {
        Binding(get: { flow.codexSourceEdit[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func update(_ change: (inout CodexDataSourceConfiguration) -> Void) {
        guard let session = flow.openWindows[.settings] else { return }
        var configuration = flow.codexSourceEdit
        change(&configuration)
        flow.send(.editCodexSource(configuration, session: session))
    }
}
