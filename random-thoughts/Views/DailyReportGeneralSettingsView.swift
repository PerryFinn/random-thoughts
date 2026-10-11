import SwiftUI

struct DailyReportGeneralSettingsView: View {
    let flow: DailyReportFlow
    @State private var timeZoneSearch = ""
    @FocusState private var focusedField: ReportSettingsValidationError?

    private var canEdit: Bool { flow.isStorageReady && !flow.isSaving }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !flow.isStorageReady {
                        Text(flow.storageError?.message ?? "正在打开本机日报设置…")
                            .foregroundStyle(flow.storageError == nil ? Color.secondary : Color.red)
                    }
                    timeZoneSettings
                    generationSettings
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .onChange(of: flow.settingsValidationError) { _, error in focusedField = error }
    }

    private var timeZoneSettings: some View {
        GroupBox("报告时区") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("模式", selection: binding(\.timeZoneMode)) {
                    Text("跟随 Mac").tag(ReportTimeZoneMode.followMac)
                    Text("固定时区").tag(ReportTimeZoneMode.fixed)
                }
                .pickerStyle(.segmented).disabled(!canEdit).pointerStyle(canEdit ? .link : .default)

                if flow.generalSettingsEdit.timeZoneMode == .fixed {
                    TextField("搜索 IANA 时区，例如 Asia/Shanghai", text: $timeZoneSearch)
                        .textFieldStyle(.roundedBorder).focused($focusedField, equals: .invalidTimeZone)
                        .disabled(!canEdit)
                    Picker("固定 IANA 时区", selection: binding(\.fixedTimeZoneIdentifier)) {
                        if !matchingTimeZones.contains(flow.generalSettingsEdit.fixedTimeZoneIdentifier) {
                            Text(flow.generalSettingsEdit.fixedTimeZoneIdentifier).tag(flow.generalSettingsEdit.fixedTimeZoneIdentifier)
                        }
                        ForEach(matchingTimeZones, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                    if flow.generalSettingsEdit.validationError == .invalidTimeZone {
                        Text(ReportSettingsValidationError.invalidTimeZone.message).foregroundStyle(.red).font(.callout)
                    }
                }

                Text("当前生效时区：\(flow.effectiveTimeZoneIdentifier ?? "无效（原值保留）")")
                    .font(.callout).textSelection(.enabled)
                if let new = flow.editedTimeZoneIdentifier, new != flow.effectiveTimeZoneIdentifier {
                    Text("保存后切换为 \(new)。旧时区 \(flow.settingsDraftImpact.count) 份草稿将被删除；保留目标时区及其他时区草稿、全部已保存日报。")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(flow.settingsDraftImpact) { day in
                        Text("\(day.calendarDate) · \(day.timeZoneIdentifier)").font(.caption)
                    }
                } else {
                    Text("编辑中的选择在保存后生效；实际时区不变时不会删除草稿。跟随 Mac 的自动变化会清除旧时区草稿并事后说明。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var generationSettings: some View {
        GroupBox("生成设置") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("日报输出语言", selection: binding(\.outputLanguage)) {
                    Text("中文").tag(ReportOutputLanguage.chinese)
                    Text("英文").tag(ReportOutputLanguage.english)
                }
                .pickerStyle(.segmented).disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                Text("生成偏好").font(.headline)
                TextEditor(text: binding(\.generationPreferences))
                    .font(.body).frame(minHeight: 120).disabled(!canEdit)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("在所选语言和固定六章节内调整语气、详略、术语与格式，不改变事实边界。")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("历史日报回看", selection: binding(\.historyLookbackDays)) {
                    ForEach(0...7, id: \.self) { Text($0 == 0 ? "不使用历史日报" : "前 \($0) 个日历日").tag($0) }
                }
                .focused($focusedField, equals: .invalidLookback)
                .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                if flow.settingsValidationError == .invalidLookback {
                    Text(ReportSettingsValidationError.invalidLookback.message).foregroundStyle(.red).font(.callout)
                }
                Text("仅取同报告时区的已保存日报，缺日不补位；历史只作背景。修改仅影响下一次生成。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if flow.settingsStorageError != nil {
                Text("常规设置保存失败；旧设置和编辑输入已保留。可重新保存。")
                    .font(.callout).foregroundStyle(.red)
            }
            HStack {
                if let notice = flow.settingsNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if flow.isSaving { ProgressView().controlSize(.small) }
                Button("撤销更改") { flow.send(.revertGeneralSettings) }
                    .disabled(!canEdit || !flow.hasGeneralSettingsEdits)
                    .pointerStyle(canEdit && flow.hasGeneralSettingsEdits ? .link : .default)
                Button(flow.isSaving ? "正在保存…" : "保存更改") { flow.send(.saveGeneralSettings) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s")
                    .disabled(!canEdit || !flow.hasGeneralSettingsEdits)
                    .pointerStyle(canEdit && flow.hasGeneralSettingsEdits ? .link : .default)
            }
        }
    }

    private var matchingTimeZones: [String] {
        ReportTimeZone.searchableIdentifiers.filter {
            timeZoneSearch.isEmpty || $0.localizedCaseInsensitiveContains(timeZoneSearch)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DailyReportGeneralSettings, Value>) -> Binding<Value> {
        let session = flow.openWindows[.settings]
        return Binding(get: { flow.generalSettingsEdit[keyPath: keyPath] }, set: { value in
            guard let session else { return }
            var settings = flow.generalSettingsEdit
            settings[keyPath: keyPath] = value
            flow.send(.editGeneralSettings(settings, session: session))
        })
    }
}
