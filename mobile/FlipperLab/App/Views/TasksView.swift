import SwiftUI

/// 任务: the running card (only while busy) and a timeline of this session's tasks (§5.8).
/// States, titles, details and times are the model's own values.
@MainActor struct TasksView: View {
    let model: AppModel

    var body: some View {
        LabPage {
            if model.busy {
                runningCard
            }
            PixelLabel("本次运行", meta: "\(model.tasks.count) 项")
            if model.tasks.isEmpty {
                EmptyPanel("还没有任务", message: "导入、保存或执行后的结果会显示在这里。")
            } else {
                LabPanel {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                            TaskTimelineRow(task: task, isLast: index == model.tasks.count - 1)
                        }
                    }
                }
            }
            Text("显示本次打开应用期间最近 100 项任务。设备确认执行后，仍需观察实际家电或硬件的响应。")
                .labFootnote()
        }
        .labNavigation("任务")
    }

    private var runningCard: some View {
        LabPanel(.emphasis) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(LabColor.ink)
                Text("正在处理…")
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
            }
            .accessibilityElement(children: .combine)
            if let running = model.tasks.first(where: { $0.state == .running }) {
                Text(verbatim: running.title)
                    .font(.body)
                    .foregroundStyle(LabColor.ink)
            }
            Button(role: .destructive) { model.cancelTask() } label: {
                Text("取消当前任务")
            }
            .buttonStyle(.labDestructive)
            .accessibilityIdentifier("tasks.cancel")
            Text("取消设备操作会断开连接；已写入设备的部分文件可能保留。")
                .labFootnote()
        }
    }
}

/// One timeline entry: state marker on a rail, badge, title, detail and start time.
private struct TaskTimelineRow: View {
    let task: TaskEntry
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                StatusBadge(state: task.state)
                Text(verbatim: task.title)
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
            }
            Text(verbatim: task.detail)
                .font(.subheadline)
                .foregroundStyle(LabColor.inkSecondary)
                .textSelection(.enabled)
            Text(task.startedAt, format: .dateTime.hour().minute().second())
                .font(LabFont.mono)
                .foregroundStyle(LabColor.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
        .padding(.bottom, isLast ? 0 : 20)
        .background(alignment: .topLeading) {
            rail
        }
        .accessibilityElement(children: .combine)
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            if !isLast {
                Rectangle()
                    .fill(LabColor.line)
                    .frame(width: 2)
                    .padding(.top, 16)
            }
            Rectangle()
                .fill(markerColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private var markerColor: Color {
        switch task.state {
        case .running: return LabColor.orange
        case .completed: return LabColor.ok
        case .failed: return LabColor.danger
        case .cancelled: return LabColor.inkTertiary
        }
    }
}
