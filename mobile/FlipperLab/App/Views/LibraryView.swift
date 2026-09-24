import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

/// 中文资料库: kind chips, real counts, record cards (§5.4). Production data stays empty
/// until the user imports; the "示例" records exist only under the DEBUG fixture argument.
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
        LabPage {
            if model.libraryReady {
                loadedContent
            } else if model.busy {
                LabProgressStrip("正在加载资料库…")
            } else {
                notLoadedPanel
            }
        }
        .labNavigation("中文资料库")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "名称、标签、备注")
        .toolbar {
            Button("导入文件", systemImage: "square.and.arrow.down") { importing = true }
                .disabled(model.busy || !model.libraryReady)
                .accessibilityIdentifier("library.import")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var loadedContent: some View {
        let shown = visible
        KindChipBar(selection: $kind)
        PixelLabel("记录", meta: "共 \(model.records.count) 条 · 显示 \(shown.count) 条")
        if model.records.isEmpty {
            EmptyPanel("这里还没有记录", message: "从 iPhone 文件或 Flipper 设备导入，随后可离线分析。") {
                Button { importing = true } label: {
                    Label("从 iPhone 文件导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.labPrimary)
                .disabled(model.busy)
                .accessibilityIdentifier("library.emptyImport")
                if model.busy {
                    ReasonNote("有任务正在进行。")
                }
            }
        } else if shown.isEmpty {
            EmptyPanel("没有匹配的记录", message: "换一个类型或关键词试试。", showsTray: false)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(shown) { record in
                    NavigationLink { RecordDetailView(model: model, id: record.id) } label: {
                        RecordCard(record: record)
                    }
                    .buttonStyle(.labCard())
                    .accessibilityLabel(cardDescription(record))
                }
            }
        }
    }

    private var notLoadedPanel: some View {
        ErrorPanel(title: "资料库尚未加载", message: "加载失败时会保留原文件，请先重试。") {
            Button("重试加载") { Task { await model.load() } }
                .buttonStyle(.labCompact)
                .disabled(model.busy)
                .accessibilityIdentifier("library.retry")
            if model.busy {
                ReasonNote("有任务正在进行。")
            }
        }
    }

    private func cardDescription(_ record: CaptureRecord) -> String {
        var parts = [record.name, record.kind.title]
        if !record.tags.isEmpty {
            parts.append("标签 " + record.tags.joined(separator: "、"))
        }
        parts.append(record.createdAt.formatted(.dateTime.year().month().day()))
        return parts.joined(separator: "，")
    }
}

/// Record card: kind tile, name, kind and tags, then date and source in monospace.
private struct RecordCard: View {
    let record: CaptureRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KindTile(kind: record.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: record.name)
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(LabColor.inkSecondary)
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 10) {
                    Text(record.createdAt, format: .dateTime.year().month().day())
                    Text(verbatim: record.sourcePath ?? "来自 iPhone 文件")
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .font(LabFont.monoCaption)
                .foregroundStyle(LabColor.inkTertiary)
                .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            LabChevron()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        record.kind.title + (record.tags.isEmpty ? "" : " · " + record.tags.joined(separator: " / "))
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
