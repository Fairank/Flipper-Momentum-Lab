import SwiftUI
import FlipperCore

/// 设备文件: the directory listing from the connected Flipper as one grouped section — path as
/// header, limits as footer (UI_APPLE_DESIGN.md §4).
@MainActor struct DeviceFilesView: View {
    let model: AppModel
    let path: String
    @State private var files: [DeviceFile] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var revision = 0

    private static let importLimit: UInt64 = 2 * 1024 * 1024

    var body: some View {
        List {
            Section {
                listing
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: path)
                        .font(LabFont.mono)
                    if !loading, failure == nil, !files.isEmpty {
                        Spacer(minLength: 8)
                        Text("\(files.count) 项")
                            .monospacedDigit()
                    }
                }
                .textCase(nil)
            } footer: {
                Text("选择文件导入手机；支持红外、Sub-GHz、NFC、RFID、iButton 和文本日志，单个文件最多 2 MiB。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(path == "/ext" ? "设备文件" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("刷新", systemImage: "arrow.clockwise") { revision += 1 }
                .disabled(model.busy || !model.device.ready)
                .accessibilityIdentifier("files.refresh")
        }
        .task(id: "\(path):\(revision)") {
            loading = true; failure = nil
            defer { loading = false }
            do {
                let result = try await model.directory(path)
                try Task.checkCancellation(); files = result
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var listing: some View {
        if loading {
            BusyRow("读取目录…")
        } else if let failure {
            ErrorRow(title: "无法读取目录", message: failure)
        } else if files.isEmpty {
            Text("此目录为空。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(files) { file in
                if file.isDirectory {
                    directoryRow(file)
                } else {
                    fileRow(file)
                }
            }
        }
    }

    private func directoryRow(_ file: DeviceFile) -> some View {
        NavigationLink { DeviceFilesView(model: model, path: file.path) } label: {
            Label {
                Text(verbatim: file.name)
                    .lineLimit(3)
            } icon: {
                Image(systemName: "folder")
            }
        }
        .disabled(model.busy)
        .accessibilityLabel("文件夹 \(file.name)")
        .accessibilityIdentifier("files.folder.\(file.name)")
    }

    private func fileRow(_ file: DeviceFile) -> some View {
        let reason = importBlockReason(file)
        return VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(verticalAlignment: .center, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: file.name)
                            .lineLimit(3)
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file))
                            .font(LabFont.mono)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("导入") { model.importDeviceFile(file) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(reason != nil)
                    .accessibilityLabel("导入 \(file.name)")
                    .accessibilityIdentifier("files.import.\(file.name)")
            }
            if let reason {
                ReasonNote(reason)
            }
        }
        .padding(.vertical, 4)
    }

    /// Same conditions as before the redesign (busy, not ready, over 2 MiB), each with its reason.
    private func importBlockReason(_ file: DeviceFile) -> String? {
        if file.size > Self.importLimit { return "超过 2 MiB，不能导入" }
        if !model.device.ready { return "需要先在“设备”页连接 Flipper。" }
        if model.busy { return "有任务正在进行" }
        return nil
    }
}
