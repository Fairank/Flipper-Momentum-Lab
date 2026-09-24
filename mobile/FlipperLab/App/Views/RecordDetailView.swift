import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

/// 记录详情: record plate, analysis, infrared keys, upload, raw preview, delete (§5.5).
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
    private var record: CaptureRecord? { model.records.first { $0.id == id } }

    var body: some View {
        LabPage {
            if let record {
                RecordPlate(record: record, busy: model.busy,
                            onEdit: { editing = true }, onExport: { exporting = true })
                AnalysisSections(report: report, failure: failure)
                if record.kind == .infrared, let buttons = report?.buttons, !buttons.isEmpty {
                    infraredSection(record, buttons: buttons)
                }
                uploadSection(record)
                RawContentSection(text: record.rawText)
                deleteSection
            } else {
                ContentUnavailableView("记录已删除", systemImage: "doc")
            }
        }
        .labNavigation(record?.name ?? "记录")
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
    }

    // MARK: Infrared — explicit, one transmission per tap

    @ViewBuilder private func infraredSection(_ record: CaptureRecord, buttons: [String]) -> some View {
        let reason = infraredBlockReason(record)
        PixelLabel("红外按钮 · 单次执行", meta: "\(buttons.count) 个")
        LazyVGrid(columns: keyColumns, alignment: .leading, spacing: 12) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { index, name in
                let spoken = "\(index + 1). \(name)"
                Button { model.sendInfrared(record, index: index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: LabFormat.twoDigits(index + 1))
                            .font(LabFont.monoCaption.weight(.semibold))
                        Text(verbatim: name)
                            .lineLimit(3)
                    }
                }
                .buttonStyle(.labKey)
                .disabled(reason != nil)
                .accessibilityLabel(spoken)
                .accessibilityIdentifier("record.irKey.\(index)")
            }
        }
        if let reason {
            ReasonNote(reason)
        }
        Text("先连接 Flipper 并上传此记录。执行前会核对设备文件；执行后请观察家电响应。")
            .labFootnote()
    }

    private var keyColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
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
            PixelLabel("上传")
            Button { model.upload(record) } label: {
                Label("上传到 Flipper", systemImage: "arrow.up.doc")
            }
            .buttonStyle(.labSecondary)
            .disabled(!model.device.ready || model.busy)
            .accessibilityIdentifier("record.upload")
            if let reason {
                ReasonNote(reason)
            }
            Text("每次生成独立文件并读回核对。中文名称和备注保存在手机。")
                .labFootnote()
        } else {
            LabPanel(.muted) {
                Text("串口日志只保存在手机，不能作为设备应用文件上传。")
                    .font(.subheadline)
                    .foregroundStyle(LabColor.inkSecondary)
            }
        }
    }

    // MARK: Delete

    @ViewBuilder private var deleteSection: some View {
        Button(role: .destructive) { deleting = true } label: {
            Label("删除手机中的记录", systemImage: "trash")
        }
        .buttonStyle(.labDestructive)
        .disabled(model.busy)
        .accessibilityIdentifier("record.delete")
        .padding(.top, 12)
        Text("只删除手机资料库中的这条记录，Flipper 上的文件会保留。")
            .labFootnote()
    }
}

/// Record plate: kind, date, source, tags, notes, and the two record actions.
private struct RecordPlate: View {
    let record: CaptureRecord
    let busy: Bool
    let onEdit: () -> Void
    let onExport: () -> Void

    var body: some View {
        LabPanel(.emphasis) {
            HStack(alignment: .center, spacing: 12) {
                KindTile(kind: record.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: record.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LabColor.inkSecondary)
                    Text(record.createdAt, format: .dateTime.year().month().day())
                        .font(LabFont.monoCaption)
                        .foregroundStyle(LabColor.inkTertiary)
                }
            }
            Text(verbatim: record.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LabColor.ink)
                .accessibilityAddTraits(.isHeader)
            PathStrip(text: record.sourcePath ?? "来自 iPhone 文件")
            if !record.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(record.tags.enumerated()), id: \.offset) { _, tag in
                        TagChip(text: tag)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("标签：" + record.tags.joined(separator: "、"))
            }
            if !record.notes.isEmpty {
                Text(verbatim: record.notes)
                    .font(.body)
                    .foregroundStyle(LabColor.ink)
                    .textSelection(.enabled)
            }
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: onEdit) {
            Label("编辑名称、标签与备注", systemImage: "pencil")
        }
        .buttonStyle(.labSecondary)
        .disabled(busy)
        .accessibilityIdentifier("record.edit")
        if busy {
            ReasonNote("有任务正在进行，暂时不能编辑。")
        }
        Button(action: onExport) {
            Label("导出原始文件", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.labSecondary)
        .accessibilityIdentifier("record.export")
        Text("导出的是原始采集内容，不包含中文名称、标签和备注。")
            .labFootnote()
    }
}

/// Bounded raw preview: the first 16,384 characters, computed without counting the whole text.
private struct RawContentSection: View {
    let text: String

    var body: some View {
        let preview = text.prefix(16_384)
        let truncated = preview.endIndex < text.endIndex
        PixelLabel("原始内容")
        Text(verbatim: String(preview))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(LabColor.ink)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LabColor.surfaceAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        if truncated {
            Text("预览仅显示前 16,384 个字符；导出包含完整内容。")
                .labFootnote()
        }
    }
}
