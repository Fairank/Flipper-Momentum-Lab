import SwiftUI

/// 任务: the running task with its cancel action (only while busy), then this session's
/// history (UI_APPLE_DESIGN.md §4). States, titles, details and times are the model's own values.
@MainActor struct TasksView: View {
    let model: AppModel

    var body: some View {
        List {
            if model.busy {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("正在处理…")
                                .font(.headline)
                            if let running = model.tasks.first(where: { $0.state == .running }) {
                                Text(verbatim: running.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Button("取消当前任务", role: .destructive) { model.cancelTask() }
                        .accessibilityIdentifier("tasks.cancel")
                } header: {
                    SectionHeader("正在进行")
                } footer: {
                    Text("取消设备操作会断开连接；已写入设备的部分文件可能保留。")
                }
            }
            Section {
                if model.tasks.isEmpty {
                    ContentUnavailableView("还没有任务", systemImage: "checklist",
                                           description: Text("导入、保存或执行后的结果会显示在这里。"))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(model.tasks) { task in
                        TaskRow(task: task)
                    }
                }
            } header: {
                SectionHeader("本次运行", count: "\(model.tasks.count) 项")
            } footer: {
                Text("显示本次打开应用期间最近 100 项任务。设备确认执行后，仍需观察实际家电或硬件的响应。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("任务")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// One task: a state symbol in its semantic colour, title, selectable detail, then the
/// state's own name with the start time — so the state never depends on colour alone.
private struct TaskRow: View {
    let task: TaskEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: task.title)
                    .font(.headline)
                Text(verbatim: task.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(task.state.rawValue) · \(task.startedAt, format: .dateTime.hour().minute().second())")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch task.state {
        case .running: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var symbolColor: Color {
        switch task.state {
        case .running: return LabColor.brandOrange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}
