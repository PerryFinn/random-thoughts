import SwiftUI

struct DailyReportGenerationStatusView: View {
    let flow: DailyReportFlow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = flow.activeGenerationDay {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("\(day.calendarDate) · \(flow.generationStage.title)")
                    VStack(alignment: .leading) {
                        Text(flow.generationScale?.description ?? "正在计算有限计划 · 尚未发送")
                        Text("归并层 \(flow.generationLayer) · 完成 \(flow.generationCompletedRequests) · 在途 \(flow.generationInFlightRequests)")
                    }.font(.caption).foregroundStyle(.secondary)
                    if let started = flow.generationStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text("\(max(0, Int(context.date.timeIntervalSince(started)))) 秒").font(.caption)
                        }
                    }
                    Spacer()
                    if flow.generationStage == .awaitingConfirmation {
                        Button("查看计划") { flow.send(.generateReport) }.pointerStyle(.link)
                    }
                    Button("取消生成") { flow.send(.cancelGeneration) }.pointerStyle(.link)
                }
            }
            if let error = flow.generationError {
                Text(error.message).font(.callout).foregroundStyle(error == .cancelled ? Color.secondary : .red)
            }
            if let retryAt = flow.generationRetryAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(ceil(retryAt.timeIntervalSince(context.date))))
                    Text(seconds > 0 ? "服务建议等待 \(seconds) 秒，之后可手动从头重试。" : "等待结束，可手动从头重试。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if flow.generationRedactionFailed {
                Text("凭据遮盖未能全部完成；内容仍可能保留秘密，可以取消。")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
    }
}
