import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

/// 资料库: kind pills, one real count and the record list (UI_APPLE_DESIGN.md §4). Both import
/// sources and 比较 sit in the toolbar. Production data stays empty until the user imports;
/// the "示例" records exist only under the DEBUG fixture argument.
@MainActor struct LibraryView: View {
    let model: AppModel
    @State private var search = ""
    @State private var kind: RecordKind?
    @State private var importing = false
    @State private var browsingDevice = false
    @State private var comparing = false
    private var visible: [CaptureRecord] {
        model.records.filter {
            (kind == nil || kind == $0.kind) && (search.isEmpty ||
                ($0.name + $0.tags.joined(separator: " ") + $0.notes + $0.kind.title).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            if model.libraryReady {
                loadedContent
            } else if model.busy {
                BusyRow("正在加载资料库…")
            } else {
                notLoadedSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("资料库")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "名称、标签、备注")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("导入文件", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(model.busy || !model.libraryReady)
                    .accessibilityIdentifier("library.import")
                moreMenu
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .navigationDestination(isPresented: $browsingDevice) {
            DeviceFilesView(model: model, path: "/ext")
        }
        .navigationDestination(isPresented: $comparing) {
            CompareRecordsView(model: model)
        }
    }

    /// 更多: both import sources and 比较. A disabled item states its reason as the subtitle.
    private var moreMenu: some View {
        let deviceReason: String? = !model.device.ready ? "需要先在“设备”页连接 Flipper。"
            : (model.busy ? "有任务正在进行。" : nil)
        return Menu {
            Button { importing = true } label: {
                Label("从 iPhone 文件导入", systemImage: "square.and.arrow.down")
            }
            .disabled(model.busy || !model.libraryReady)
            Button { browsingDevice = true } label: {
                Label("从 Flipper 导入", systemImage: "arrow.down.doc")
                Text(deviceReason ?? "浏览设备存储，把文件导入资料库。")
            }
            .disabled(deviceReason != nil)
            .accessibilityIdentifier("library.importDevice")
            Button { comparing = true } label: {
                Label("比较两次记录", systemImage: "rectangle.split.2x1")
            }
            .accessibilityIdentifier("library.compare")
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(LabColor.accent)
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("library.more")
    }

    @ViewBuilder private var loadedContent: some View {
        if model.records.isEmpty {
            Section {
                ContentUnavailableView {
                    Label {
                        Text("这里还没有记录")
                    } icon: {
                        PixelBitmapView(bitmap: PixelSprites.tray, unit: 4, color: .secondary)
                    }
                } description: {
                    Text("从 iPhone 文件或 Flipper 导入采集文件；统计、图表和比较都在手机本地完成，不上传云端。")
                }
                .listRowBackground(Color.clear)
                // Keep the full-width action in its own bounded list row. The unavailable
                // view's action layout can reduce it to an oversized icon-only capsule.
                VStack(spacing: 12) {
                    Button { importing = true } label: {
                        PrimaryButtonLabel(title: "从 iPhone 文件导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(LabColor.brandOrange)
                    .disabled(model.busy)
                    .accessibilityIdentifier("library.emptyImport")
                    if model.busy {
                        ReasonNote("有任务正在进行。")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else {
            let shown = visible
            Section {
                KindFilterBar(selection: $kind)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                if shown.isEmpty {
                    ContentUnavailableView("没有匹配的记录", systemImage: "magnifyingglass",
                                           description: Text("换一个类型或关键词试试。"))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(shown) { record in
                        NavigationLink { RecordDetailView(model: model, id: record.id) } label: {
                            RecordRow(record: record)
                        }
                        .accessibilityLabel(rowDescription(record))
                    }
                }
            } header: {
                SectionHeader("记录", count: shown.count == model.records.count
                              ? "共 \(model.records.count) 条" : "显示 \(shown.count) 条")
            }
        }
    }

    private var notLoadedSection: some View {
        Section {
            ErrorRow(title: "资料库尚未加载", message: "加载失败时会保留原文件，请先重试。") {
                Button("重试加载") { Task { await model.load() } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(model.busy)
                    .accessibilityIdentifier("library.retry")
                if model.busy {
                    ReasonNote("有任务正在进行。")
                }
            }
        }
    }

    private func rowDescription(_ record: CaptureRecord) -> String {
        var parts = [record.name, record.kind.title]
        if !record.tags.isEmpty {
            parts.append("标签 " + record.tags.joined(separator: "、"))
        }
        parts.append(record.createdAt.formatted(.dateTime.year().month().day()))
        return parts.joined(separator: "，")
    }
}

/// Record row: kind tile, name, kind and tags, then the date and source in the default face.
private struct RecordRow: View {
    let record: CaptureRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KindTile(kind: record.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: record.name)
                    .font(.headline)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                    Text(record.createdAt, format: .dateTime.year().month().day())
                    Text(verbatim: record.sourcePath ?? "来自 iPhone 文件")
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
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
