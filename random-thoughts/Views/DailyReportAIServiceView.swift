import SwiftUI

struct DailyReportAIServiceView: View {
    let flow: DailyReportFlow
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case endpoint, model, temperature, defaults, totalBudget, outputLimit, concurrency, credential }
    private var canEdit: Bool { flow.isStorageReady && !flow.isSaving && !flow.isValidatingAIService }
    private var canRead: Bool { canEdit && !flow.isReadingAICredential && flow.aiCredentialStatus == .readable }

    var body: some View {
        VStack(spacing: 12) {
            Picker("AI 服务协议", selection: Binding(get: { flow.aiServiceEdit.configuration.service }, set: { flow.send(.selectAIServiceType($0)) })) {
                ForEach(AIServiceType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !flow.isStorageReady { Text(flow.storageError?.message ?? "正在打开本机日报设置…").foregroundStyle(.secondary) }
                    endpointAndModel
                    defaultsAndBudget
                    credentials
                    validation
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if flow.isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("撤销更改") { flow.send(.revertAIService) }
                    .disabled(!canEdit || !flow.hasAIServiceEdits).pointerStyle(canEdit && flow.hasAIServiceEdits ? .link : .default)
                Button(flow.isSaving ? "正在保存…" : "保存配置") {
                    flow.send(.saveAIService)
                    focusError()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut("s")
                .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
            }
        }
        .onChange(of: flow.aiServiceInputError) { _, _ in focusError() }
        .onChange(of: flow.aiCredentialError) { _, error in if error != nil { focusedField = .credential } }
    }

    private var endpointAndModel: some View {
        GroupBox("请求目标") {
            VStack(alignment: .leading, spacing: 10) {
                Text("完整请求端点").font(.headline)
                TextField(flow.aiServiceEdit.configuration.service.endpointExample, text: configurationBinding(\.endpoint))
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .endpoint).disabled(!canEdit)
                if flow.aiServiceUsesPlainHTTP {
                    Label("明文 HTTP：请求内容与凭据将以明文传输。", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                fieldError(.endpoint)
                Text("直接使用完整 URL，保留路径、query 和尾斜杠。").font(.caption).foregroundStyle(.secondary)
                Text("精确模型标识").font(.headline)
                TextField("按此端点的约定填写模型", text: configurationBinding(\.model))
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .model).disabled(!canEdit)
                fieldError(.model)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var defaultsAndBudget: some View {
        GroupBox("服务生成默认值与请求预算") {
            VStack(alignment: .leading, spacing: 10) {
                TextField(flow.aiServiceEdit.configuration.service == .messages ? "温度（0–1，留空未设置）" : "温度（0–2，留空未设置）",
                          text: editBinding(\.temperature))
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .temperature).disabled(!canEdit)
                fieldError(.temperature)
                AIServiceDefaultsEditor(defaults: configurationBinding(\.defaults), canEdit: canEdit)
                    .focused($focusedField, equals: .defaults)
                fieldError(.defaults)
                Divider()
                numericField("请求总预算 C", keyPath: \.totalBudget, field: .totalBudget)
                numericField("输出上限 O", keyPath: \.outputLimit, field: .outputLimit)
                numericField("并发数（1–8）", keyPath: \.concurrency, field: .concurrency)
                Text("C 必须大于 O。O 包含服务计入的思考额度；这些值不证明模型的实际容量。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var credentials: some View {
        GroupBox("AI 服务凭据") {
            VStack(alignment: .leading, spacing: 10) {
                Text("已保存：\(flow.aiCredentialStatus.title)").font(.headline)
                if flow.savedAIService.credential != nil {
                    Text(flow.revealedAICredential ?? "••••••••")
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button(flow.revealedAICredential == nil ? "显示已保存凭据" : "隐藏凭据") {
                        flow.send(flow.revealedAICredential == nil ? .showAICredential : .hideAICredential)
                    }
                    .disabled(!canRead).pointerStyle(canRead ? .link : .default)
                    Button("复制已保存凭据") { flow.send(.copyAICredential) }
                        .disabled(!canRead).pointerStyle(canRead ? .link : .default)
                    if flow.isReadingAICredential { ProgressView().controlSize(.small) }
                }
                if case .unreadable(let error) = flow.aiCredentialStatus { Text(error.message).font(.callout).foregroundStyle(.red) }
                SecureField("新凭据（留空保留旧值）", text: editBinding(\.newCredential))
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .credential).disabled(!canEdit)
                fieldError(.credential)
                if let error = flow.aiCredentialError { Text(error.message).font(.callout).foregroundStyle(.red) }
                Text("配置与加密凭据一起保存；密钥随应用提供，不绑定设备。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("删除已保存凭据…", role: .destructive) { flow.send(.requestDeleteAICredential) }
                    .disabled(!canEdit || flow.hasAIServiceEdits || flow.savedAIService.credential == nil)
                    .pointerStyle(canEdit && !flow.hasAIServiceEdits && flow.savedAIService.credential != nil ? .link : .default)
                if flow.hasAIServiceEdits, flow.savedAIService.credential != nil {
                    Text("删除前请先保存或撤销未保存配置。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var validation: some View {
        GroupBox("校验与当前配置") {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前 AI 服务：\(flow.currentAIService?.title ?? "尚未选择")").font(.headline)
                Text("已保存配置：\(flow.savedAIService.validation.status.title)")
                Text("流式：\(flow.savedAIService.validation.streaming.title) · 结构化：\(flow.savedAIService.validation.structured.title)")
                    .font(.callout)
                Text(flow.aiServiceEdit.configuration.service == .chatCompletions
                     ? "显式校验最多发送三次少量合成请求（基础、流式、结构化），可能计费；不发送工作正文或生成偏好。"
                     : "此协议校验尚未接入。保存、切换和启动不发送请求。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("校验已保存配置") { flow.send(.requestAIValidation); focusError() }
                        .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
                    Button("设为当前") { flow.send(.makeAIServiceCurrent) }
                        .disabled(!flow.canMakeAIServiceCurrent).pointerStyle(flow.canMakeAIServiceCurrent ? .link : .default)
                }
                if flow.isValidatingAIService {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在校验：\(flow.aiValidationStage?.rawValue ?? "准备")")
                        Button("取消校验") { flow.send(.cancelAIValidation) }.pointerStyle(.link)
                    }
                }
                if flow.aiServiceStorageError != nil {
                    Text("本地提交失败，完整旧配置和当前输入保留。请重试保存。")
                        .font(.callout).foregroundStyle(.red)
                }
                if let notice = flow.aiServiceNotice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private func numericField(_ title: String, keyPath: WritableKeyPath<AIServiceEdit, String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, text: editBinding(keyPath)).textFieldStyle(.roundedBorder).frame(width: 140)
                    .focused($focusedField, equals: field).disabled(!canEdit)
            }
            fieldError(field)
        }
    }
    @ViewBuilder private func fieldError(_ field: Field) -> some View {
        if errorField == field, let error = flow.aiServiceInputError { Text(error.message).font(.callout).foregroundStyle(.red) }
    }
    private var errorField: Field? {
        switch flow.aiServiceInputError {
        case .invalidEndpoint, .missingEndpoint: .endpoint
        case .missingModel: .model
        case .invalidTemperature: .temperature
        case .invalidDefaults: .defaults
        case .invalidTotalBudget: .totalBudget
        case .invalidOutputLimit: .outputLimit
        case .invalidConcurrency: .concurrency
        case .missingCredential: .credential
        case nil: nil
        }
    }
    private func focusError() { if let errorField { focusedField = errorField } }
    private func editBinding<Value>(_ keyPath: WritableKeyPath<AIServiceEdit, Value>) -> Binding<Value> {
        let session = flow.openWindows[.settings]
        let revision = flow.aiServiceEditRevision
        return Binding(get: { flow.aiServiceEdit[keyPath: keyPath] }, set: { value in
            guard let session else { return }
            var edit = flow.aiServiceEdit
            edit[keyPath: keyPath] = value
            flow.send(.editAIService(edit, session: session, revision: revision))
        })
    }
    private func configurationBinding<Value>(_ keyPath: WritableKeyPath<AIServiceConfiguration, Value>) -> Binding<Value> {
        let configuration = editBinding(\.configuration)
        return Binding(get: { configuration.wrappedValue[keyPath: keyPath] }, set: { value in
            var edited = configuration.wrappedValue
            edited[keyPath: keyPath] = value
            configuration.wrappedValue = edited
        })
    }
}
