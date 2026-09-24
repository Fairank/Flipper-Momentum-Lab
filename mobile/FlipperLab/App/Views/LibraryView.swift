import SwiftUI
import Charts
import UniformTypeIdentifiers
import FlipperCore

@MainActor struct LibraryView: View {
    let model: AppModel
    @State private var search = ""
    @State private var kind: RecordKind?
    @State private var importing = false
    private var visible: [CaptureRecord] {
        model.records.filter {
            (kind == nil || kind == $0.kind) && (search.isEmpty ||
                ($0.name + $0.tags.joined(separator: " ") + $0.notes + $0.kind.title).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            if !model.libraryReady {
                Text("资料库尚未加载。加载失败时会保留原文件，请先重试。")
                Button("重试加载") { Task { await model.load() } }.disabled(model.busy)
            }
            Section {
                Picker("类型", selection: $kind) {
                    Text("全部").tag(nil as RecordKind?)
                    ForEach(RecordKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
            }
            if visible.isEmpty {
                ContentUnavailableView("这里还没有记录", systemImage: "tray", description: Text("从 iPhone 文件或 Flipper 设备导入，随后可离线分析。"))
            }
            ForEach(visible) { record in
                NavigationLink { RecordDetailView(model: model, id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.name).font(.headline)
                        Text(record.kind.title + (record.tags.isEmpty ? "" : " · " + record.tags.joined(separator: " / ")))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(record.createdAt, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("中文资料库").searchable(text: $search, prompt: "名称、标签、备注")
        .toolbar { Button("导入文件", systemImage: "square.and.arrow.down") { importing = true }.disabled(model.busy || !model.libraryReady) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
    }
}

struct RawRecordDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let value = String(data: data, encoding: .utf8) else { throw RPCError.malformed }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

@MainActor struct RecordDetailView: View {
    let model: AppModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var report: AnalysisReport?
    @State private var failure: String?
    @State private var editing = false
    @State private var deleting = false
    @State private var exporting = false
    private var record: CaptureRecord? { model.records.first { $0.id == id } }
    var body: some View {
        List {
            if let record {
                Section("记录") {
                    LabeledContent("类型", value: record.kind.title)
                    if !record.tags.isEmpty { Text("标签：" + record.tags.joined(separator: "、")) }
                    if !record.notes.isEmpty { Text(record.notes) }
                    Text(record.sourcePath ?? "来自 iPhone 文件").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("编辑名称、标签与备注", systemImage: "pencil") { editing = true }.disabled(model.busy)
                    Button("导出原始文件", systemImage: "square.and.arrow.up") { exporting = true }
                }
                if let report {
                    AnalysisSections(report: report)
                    if record.kind == .infrared && !report.buttons.isEmpty {
                        Section {
                            ForEach(Array(report.buttons.enumerated()), id: \.offset) { index, name in
                                Button { model.sendInfrared(record, index: index) } label: {
                                    Label("\(index + 1). \(name)", systemImage: "dot.radiowaves.left.and.right")
                                }.disabled(!model.device.ready || model.busy || record.sourcePath?.hasPrefix("/ext/infrared/") != true)
                            }
                        } header: { Text("红外按钮 · 单次执行") } footer: {
                            Text("先连接 Flipper 并上传此记录。执行前会核对设备文件；执行后请观察家电响应。")
                        }
                    }
                } else if let failure { Text(failure).foregroundStyle(.red) }
                else { ProgressView("正在分析…") }
                if record.kind.deviceDirectory != nil {
                    Section {
                        Button("上传到 Flipper", systemImage: "arrow.up.doc") { model.upload(record) }
                            .disabled(!model.device.ready || model.busy)
                    } footer: { Text("每次生成独立文件并读回核对。中文名称和备注保存在手机。") }
                }
                Section("原始内容") {
                    Text(String(record.rawText.prefix(16_384))).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    if record.rawText.count > 16_384 { Text("预览仅显示前 16,384 个字符；导出包含完整内容。").font(.footnote).foregroundStyle(.secondary) }
                }
                Section { Button("删除手机中的记录", role: .destructive) { deleting = true }.disabled(model.busy) }
            } else { ContentUnavailableView("记录已删除", systemImage: "doc") }
        }
        .navigationTitle(record?.name ?? "记录").navigationBarTitleDisplayMode(.inline)
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
}

@MainActor struct AnalysisSections: View {
    let report: AnalysisReport
    var body: some View {
        Section("分析结果") {
            ForEach(Array(report.facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.title).font(.caption).foregroundStyle(.secondary)
                    Text(fact.value).textSelection(.enabled)
                }
            }
            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
        if !report.pulseDurations.isEmpty {
            Section("包络时序") {
                Chart(Array(report.pulseDurations.enumerated()), id: \.offset) { index, duration in
                    BarMark(x: .value("顺序", index + 1), y: .value("微秒", duration))
                }.frame(height: 180).accessibilityLabel("脉冲时序图，共 \(report.pulseDurations.count) 个采样间隔，单位微秒")
                Text("横轴为记录顺序，纵轴为持续时间（微秒）。最多显示 512 个点；数据较多时按区间取代表值，统计仍覆盖全部数据。这是包络时序。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor struct EditRecordView: View {
    let model: AppModel
    @State var record: CaptureRecord
    @State private var tags = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("中文名称", text: $record.name)
            TextField("标签，用逗号分隔", text: $tags)
            Section("备注") { TextEditor(text: $record.notes).frame(minHeight: 140) }
            Text("只修改手机资料库里的名称与说明，保留原始采集数据。").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("编辑记录")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving && model.busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    record.tags = tags.replacingOccurrences(of: "，", with: ",").split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    saving = true; model.saveRecord(record)
                }.disabled(model.busy || record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { tags = record.tags.joined(separator: ", ") }
        .onChange(of: model.busy) { _, busy in
            if saving && !busy {
                saving = false
                if model.error == nil { dismiss() }
            }
        }
        .interactiveDismissDisabled(saving && model.busy)
    }
}
