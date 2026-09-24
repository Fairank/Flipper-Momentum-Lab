import SwiftUI
import FlipperCore

/// 设备文件: path strip, then the directory listing from the connected Flipper (§5.2).
@MainActor struct DeviceFilesView: View {
    let model: AppModel
    let path: String
    @State private var files: [DeviceFile] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var revision = 0

    private static let importLimit: UInt64 = 2 * 1024 * 1024

    var body: some View {
        LabPage {
            PathStrip(text: path)
            Text("选择文件导入手机；支持红外、Sub-GHz、NFC、RFID、iButton 和文本日志，单个文件最多 2 MiB。")
                .labFootnote()
            listing
        }
        .labNavigation(path == "/ext" ? "设备文件" : (path as NSString).lastPathComponent)
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
            LabPanel {
                ProgressView("读取目录…")
                    .tint(LabColor.ink)
                    .foregroundStyle(LabColor.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        } else if let failure {
            ErrorPanel(title: "无法读取目录", message: failure)
        } else if files.isEmpty {
            LabPanel {
                Text("此目录为空。")
                    .font(.subheadline)
                    .foregroundStyle(LabColor.inkSecondary)
            }
        } else {
            PixelLabel("目录内容", meta: "\(files.count) 项")
            LabPanel(padded: false) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    if index > 0 {
                        LabDivider()
                    }
                    if file.isDirectory {
                        directoryRow(file)
                    } else {
                        fileRow(file)
                    }
                }
            }
        }
    }

    private func directoryRow(_ file: DeviceFile) -> some View {
        NavigationLink { DeviceFilesView(model: model, path: file.path) } label: {
            HStack(spacing: 12) {
                SymbolTile(systemName: "folder", size: 36)
                Text(verbatim: file.name)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                LabChevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.labRow)
        .disabled(model.busy)
        .accessibilityLabel("文件夹 \(file.name)")
        .accessibilityIdentifier("files.folder.\(file.name)")
    }

    private func fileRow(_ file: DeviceFile) -> some View {
        let reason = importBlockReason(file)
        return VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(verticalAlignment: .center, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    SymbolTile(systemName: "doc.plaintext", size: 36, fill: LabColor.surfaceAlt)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: file.name)
                            .font(.headline)
                            .foregroundStyle(LabColor.ink)
                            .lineLimit(3)
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file))
                            .font(LabFont.mono)
                            .foregroundStyle(LabColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button("导入") { model.importDeviceFile(file) }
                    .buttonStyle(.labCompact)
                    .disabled(reason != nil)
                    .accessibilityLabel("导入 \(file.name)")
                    .accessibilityIdentifier("files.import.\(file.name)")
            }
            if let reason {
                ReasonNote(reason)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Same conditions as before the redesign (busy, not ready, over 2 MiB), each with its reason.
    private func importBlockReason(_ file: DeviceFile) -> String? {
        if file.size > Self.importLimit { return "超过 2 MiB，不能导入" }
        if !model.device.ready { return "需要先在“设备”页连接 Flipper。" }
        if model.busy { return "有任务正在进行" }
        return nil
    }
}
