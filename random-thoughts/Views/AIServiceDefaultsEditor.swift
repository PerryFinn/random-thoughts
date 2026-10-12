import SwiftUI

struct AIServiceDefaultsEditor: View {
    @Binding var defaults: AIServiceDefaults
    let canEdit: Bool

    var body: some View {
        switch defaults {
        case .chatCompletions(let value):
            reasoningPicker("reasoning_effort", selection: Binding(get: { value.reasoningEffort }, set: { effort in
                var edited = value; edited.reasoningEffort = effort; defaults = .chatCompletions(edited)
            }))
        case .responses(let value):
            reasoningPicker("reasoning.effort", selection: Binding(get: { value.reasoningEffort }, set: { effort in
                var edited = value; edited.reasoningEffort = effort; defaults = .responses(edited)
            }))
        case .messages(let value):
            Picker("thinking", selection: Binding(get: { value.thinking }, set: { thinking in
                var edited = value
                edited.thinking = thinking
                if thinking != .adaptive { edited.effort = nil }
                defaults = .messages(edited)
            })) {
                Text("端点默认").tag(MessagesThinking.endpointDefault)
                Text("关闭").tag(MessagesThinking.disabled)
                Text("adaptive").tag(MessagesThinking.adaptive)
            }
            .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
            if value.thinking == .adaptive {
                Picker("output_config.effort", selection: Binding(get: { value.effort }, set: { effort in
                    var edited = value; edited.effort = effort; defaults = .messages(edited)
                })) {
                    Text("未设置").tag(MessagesEffort?.none)
                    ForEach(MessagesEffort.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
            }
        }
    }

    private func reasoningPicker(_ label: String, selection: Binding<AIReasoningEffort?>) -> some View {
        Picker(label, selection: selection) {
            Text("未设置").tag(AIReasoningEffort?.none)
            ForEach(AIReasoningEffort.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
        .disabled(!canEdit).pointerStyle(canEdit ? .link : .default)
    }
}
