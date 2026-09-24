import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

/// 记录详情: header, analysis, infrared keys, upload and raw preview as grouped sections
/// (UI_APPLE_DESIGN.md §4). 编辑 is a toolbar button; 导出, 比较 and 删除 are in its 更多 menu.
@MainActor struct RecordDetailView: View {
    let model: AppModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var report: AnalysisReport?
    @State private var failure: String?
    @State private var editing = false
    @State private var deleting = false
    @State private var exporting = false
    @State private var comparing = false
    private var record: CaptureRecord? { model.records.first { $0.id == id } }

    var body: some View {
        List {
            if let record {
                RecordHeaderSection(record: record, busy: model.busy)
                AnalysisSections(report: report, failure: failure)
                if record.kind == .infrared, let buttons = report?.buttons, !buttons.isEmpty {
                    infraredSection(record, buttons: buttons)
                }
                uploadSection(record)
                RawContentSection(text: record.rawText)
            } else {
                ContentUnavailableView("记录已删除", systemImage: "doc")
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(record?.name ?? "记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("编辑") { editing = true }
                    .disabled(record == nil || model.busy)
                    .accessibilityIdentifier("record.edit")
                recordMenu
            }
        }
        .task(id: record?.id) {
            guard let record else { return }
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try RecordAnalyzer.analyze(record.rawText, kind: record.kind)
                }.value
                try Task.checkCancellation(); report = value
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
        .sheet(isPresented: $editing) {
            if let record { NavigationStack { EditRecordView(model: model, record: record) } }
        }
        .fileExporter(isPresented: $exporting, document: RawRecordDocument(text: record?.rawText ?? ""), contentType: .data,
                      defaultFilename: "Lab_\(id.uuidString).\(record?.kind.fileExtension ?? "txt")") { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .confirmationDialog("删除此手机记录？设备上的文件会保留。", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) { model.deleteRecord(id) }
        }
        .onChange(of: record == nil) { _, removed in if removed { dismiss() } }
        .navigationDestination(isPresented: $comparing) {
            CompareRecordsView(model: model, initialFirst: id)
        }
    }

    /// 更多: export, compare with this record as A, and delete (which still asks first).
    private var recordMenu: some View {
        Menu {
            Button { exporting = true } label: {
                Label("导出原始文件", systemImage: "square.and.arrow.up")
                Text("原始采集内容，不含中文名称、标签和备注")
            }
            .accessibilityIdentifier("record.export")
            Button { comparing = true } label: {
                Label("与其他记录比较", systemImage: "rectangle.split.2x1")
            }
            .accessibilityIdentifier("record.compare")
            Divider()
            Button(role: .destructive) { deleting = true } label: {
                Label("删除记录", systemImage: "trash")
                Text(model.busy ? "有任务正在进行。" : "只删除手机中的记录，Flipper 上的文件会保留")
            }
            .disabled(model.busy)
            .accessibilityIdentifier("record.delete")
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(LabColor.accent)
        }
        .disabled(record == nil)
        .accessibilityLabel("更多")
        .accessibilityIdentifier("record.more")
    }

    // MARK: Infrared — explicit, one transmission per tap

    @ViewBuilder private func infraredSection(_ record: CaptureRecord, buttons: [String]) -> some View {
        let reason = infraredBlockReason(record)
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        Section {
            if let reason {
                ReasonNote(reason)
            }
            // Keep each pair a separate List row: large remote libraries must not create
            // every button at once. The reason remains above the controls, even for many keys.
            ForEach(Array(stride(from: 0, to: buttons.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(start..<min(start + columns, buttons.count), id: \.self) { index in
                        infraredKey(record, name: buttons[index], index: index, disabled: reason != nil)
                    }
                    if start + columns > buttons.count {
                        // Keeps a lone last key at the same width as the others.
                        Color.clear
                            .frame(height: 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            SectionHeader("红外按钮 · 单次执行", count: "\(buttons.count) 个")
        } footer: {
            Text("先连接 Flipper 并上传此记录。执行前会核对设备文件；执行后请观察家电响应。")
        }
    }

    private func infraredKey(_ record: CaptureRecord, name: String, index: Int, disabled: Bool) -> some View {
        let spoken = "\(index + 1). \(name)"
        return Button { model.sendInfrared(record, index: index) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: LabFormat.twoDigits(index + 1))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(verbatim: name)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .controlSize(.large)
        .disabled(disabled)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("record.irKey.\(index)")
    }

    /// Non-nil exactly when the keys are disabled: not ready, busy, or the source is not a
    /// device infrared file (the same guard as before the redesign), in priority order.
    private func infraredBlockReason(_ record: CaptureRecord) -> String? {
        if !model.device.ready { return "先在“设备”页连接 Flipper。" }
        guard let path = record.sourcePath else { return "此记录来自 iPhone 文件，需先上传到 Flipper 才能执行。" }
        if !path.hasPrefix("/ext/infrared/") { return "设备来源不在 /ext/infrared/ 目录，需先上传到 Flipper 才能执行。" }
        if model.busy { return "有任务正在进行。" }
        return nil
    }

    // MARK: Upload

    @ViewBuilder private func uploadSection(_ record: CaptureRecord) -> some View {
        if record.kind.deviceDirectory != nil {
            let reason: String? = !model.device.ready ? "需要先在“设备”页连接 Flipper。"
                : (model.busy ? "有任务正在进行。" : nil)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Button { model.upload(record) } label: {
                        WideButtonLabel(title: "上传到 Flipper", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.device.ready || model.busy)
                    .accessibilityIdentifier("record.upload")
                    if let reason {
                        ReasonNote(reason)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                SectionHeader("上传")
            } footer: {
                Text("每次生成独立文件并读回核对。中文名称和备注保存在手机。")
            }
        } else {
            Section {
                Text("串口日志只保存在手机，不能作为设备应用文件上传。")
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("上传")
            }
        }
    }
}

/// Record header: kind tile, name, kind and date, source, tags, notes, and — while a task
/// runs — why 编辑 is unavailable.
private struct RecordHeaderSection: View {
    let record: CaptureRecord
    let busy: Bool

    var body: some View {
        Section {
            AdaptiveStack(verticalAlignment: .center, spacing: 12) {
                KindTile(kind: record.kind, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: record.name)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(record.kind.title) · \(record.createdAt, format: .dateTime.year().month().day())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            source
            if !record.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(record.tags.enumerated()), id: \.offset) { _, tag in
                        TagCapsule(text: tag)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("标签：" + record.tags.joined(separator: "、"))
            }
            if !record.notes.isEmpty {
                Text(verbatim: record.notes)
                    .textSelection(.enabled)
            }
            if busy {
                ReasonNote("有任务正在进行，暂时不能编辑。")
            }
        }
    }

    @ViewBuilder private var source: some View {
        if let path = record.sourcePath {
            Label {
                Text(verbatim: path)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "folder")
            }
            .font(LabFont.mono)
        } else {
            Label("来自 iPhone 文件", systemImage: "iphone")
                .font(.subheadline)
        }
    }
}

/// Bounded raw preview: the first 16,384 characters, computed without counting the whole text.
private struct RawContentSection: View {
    let text: String

    var body: some View {
        let preview = text.prefix(16_384)
        let truncated = preview.endIndex < text.endIndex
        Section {
            Text(verbatim: String(preview))
                .font(LabFont.monoCaption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            SectionHeader("原始内容")
        } footer: {
            if truncated {
                Text("预览仅显示前 16,384 个字符；导出包含完整内容。")
            }
        }
    }
}
