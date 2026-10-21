import SwiftUI

struct DailyReportContentManagementView: View {
    let flow: DailyReportFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("本机日报内容").font(.title2)
                    if let error = flow.storageError {
                        Text(error.message).foregroundStyle(.red).textSelection(.enabled)
                    }
                    GroupBox("持久保存与窗口内存分别统计") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(flow.isStorageReady ? "已保存日报：\(flow.contentCounts.saved) 份（全部日期及报告时区）" : "已保存日报：存储不可用，数量未知")
                            Text("本窗口内存草稿：\(flow.contentCounts.drafts) 份")
                            Text("本窗口已确认快照：\(flow.contentCounts.snapshots) 份")
                            Text("草稿和快照没有磁盘副本；真正关闭日报窗口后归零。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    if flow.isStorageReady {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(flow.savedReports.keys.sorted {
                                ($0.calendarDate, $0.timeZoneIdentifier) > ($1.calendarDate, $1.timeZoneIdentifier)
                            }) { day in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(day.calendarDate)
                                        Text(day.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("删除", role: .destructive) { flow.send(.requestDeleteReport(day, window: .settings)) }
                                        .disabled(flow.isSaving).pointerStyle(flow.isSaving ? .default : .link)
                                }
                                Divider()
                            }
                        }
                    }
                    GroupBox("人工整体备份与恢复") {
                        Text("完全退出应用并确认没有其他实例写入后，整体复制或替换专属数据目录，包含必要 SQLite journal；不要混搭不同副本。只关闭日报窗口不算停机。使用兼容应用恢复，旧副本可能带回已删除日报、旧 Key 和旧设置；不会恢复草稿或自动联网。")
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(8)
                    }
                    Button("打开日报数据文件夹") { flow.send(.openReportDataDirectory) }
                        .disabled(flow.isSaving).pointerStyle(flow.isSaving ? .default : .link)
                    if flow.storageError != nil {
                        GroupBox("重置日报功能数据") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("请先尝试修复权限、磁盘空间或使用兼容应用。重置会删除整个日报库、事务状态、全部日报设置和凭据；与普通清空不同。中断后继续已确认重置，不保留旧库备份。")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("重置日报功能数据…", role: .destructive) { flow.send(.requestResetReportData) }
                                    .disabled(!flow.canResetReportData).pointerStyle(flow.canResetReportData ? .link : .default)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if flow.isSaving { ProgressView().controlSize(.small) }
                if let notice = flow.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("清空全部日报内容…", role: .destructive) { flow.send(.requestClearReports) }
                    .disabled(!flow.isStorageReady || flow.isSaving)
                    .pointerStyle(flow.isStorageReady && !flow.isSaving ? .link : .default)
            }
            Text("普通清空保留设置和凭据、模型监控、蓝牙配置及 Codex 原会话。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
