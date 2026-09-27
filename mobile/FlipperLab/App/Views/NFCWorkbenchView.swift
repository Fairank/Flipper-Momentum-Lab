import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

@MainActor struct NFCWorkbenchView: View {
    @State private var workbench = NFCWorkbenchModel()
    @State private var importing = false
    @State private var importDictionary = false
    @State private var exporting = false
    @State private var exportText = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                Label("MIFARE Classic", systemImage: "wave.3.right")
                    .font(.headline)
                Text("导入自有测试卡的两组认证样本，在手机上恢复或验证密钥。支持 Flipper 的 .mfkey32.log；普通 .nfc 卡片备份不能代替认证样本。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button("导入认证样本") { importDictionary = false; importing = true }
                    .accessibilityIdentifier("nfc.importSamples")
                LabeledContent("有效样本", value: "\(workbench.samples.count) 组")
                Button("导入并合并字典") { importDictionary = true; importing = true }
                LabeledContent("去重后的候选密钥", value: "\(workbench.dictionary?.keys.count ?? 0) 个")
                Button("导出合并字典") {
                    exportText = workbench.dictionary?.text ?? ""; exporting = true
                }.disabled(workbench.dictionary == nil)
                Button("载入公开测试样本") { workbench.loadExample() }
                    .accessibilityIdentifier("nfc.loadExample")
            } header: { SectionHeader("分析材料") }
              footer: { Text("字典仅合并你导入的密钥，保留顺序并去除重复项。单文件上限 2 MiB，最多 10 万个候选密钥、64 组样本。") }
              .disabled(workbench.running)
            Section {
                Picker("计算方式", selection: $workbench.recoveryMode) {
                    Text("密钥恢复").tag(true)
                    Text("字典验证").tag(false)
                }.disabled(workbench.running)
                if workbench.running {
                    ProgressView(value: workbench.fraction) { Text(workbench.status) }
                    Button("取消分析", role: .destructive) { workbench.cancel() }
                } else {
                    Button("开始离线分析") { workbench.verify() }
                        .disabled((!workbench.recoveryMode && workbench.dictionary == nil) || workbench.samples.isEmpty)
                        .accessibilityIdentifier("nfc.verify")
                    Text(workbench.status).foregroundStyle(.secondary)
                        .accessibilityIdentifier("nfc.status")
                }
                if let error = workbench.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red).font(.subheadline)
                }
            } header: { SectionHeader("手机计算") }
              footer: { Text(workbench.recoveryMode
                  ? "密钥恢复使用 MFKey32 算法，不依赖字典。仅适用于符合条件的 MIFARE Classic 认证样本，不支持所有 NFC 卡型。每次计算使用约 17 MiB 工作内存，结果须再通过两组样本复核。"
                  : "字典验证只在候选字典中查找匹配项。未命中表示当前字典没有找到答案。计算和文件均留在手机。") }
            if !workbench.results.isEmpty {
                Section {
                    ForEach(Array(workbench.results.enumerated()), id: \.offset) { _, result in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("扇区 \(result.sample.sector) · Key \(result.sample.keyType)").font(.headline)
                            Text(String(format: "CUID %08X", result.sample.cuid))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            Text(result.key ?? "本次未找到匹配密钥")
                                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    Button("导出已验证密钥") {
                        exportText = workbench.verifiedText; exporting = true
                    }.disabled(workbench.verifiedText.isEmpty)
                    Button("把已验证密钥加入字典") { workbench.mergeVerified() }
                        .disabled(workbench.verifiedText.isEmpty || workbench.running)
                } header: { SectionHeader("验证结果") }
                  footer: { Text("命中的密钥已通过两组认证数据复核。导出的 .nfc 文件是密钥字典，不是可直接刷门的卡片文件。") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("NFC 离线工作台")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: importDictionary) { result in
            switch result {
            case .success(let urls): workbench.importFiles(urls, dictionary: importDictionary)
            case .failure(let error): workbench.error = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $exporting, document: SerialDataDocument(data: Data(exportText.utf8)),
                      contentType: .data, defaultFilename: "Flipper-verified-keys.nfc") { result in
            if case .failure(let error) = result { workbench.error = error.localizedDescription }
        }
        .onDisappear { workbench.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { workbench.cancel() } }
    }
}

@MainActor @Observable private final class NFCWorkbenchModel {
    var samples: [ClassicSample] = []
    var dictionary: NFCKeyDictionary?
    var results: [ClassicMatch] = []
    var recoveryMode = true
    var running = false
    var fraction = 0.0
    var status = "导入材料后即可开始，不需要连接 Flipper。"
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var verifiedText: String {
        var seen: Set<String> = []
        let keys = results.compactMap(\.key).filter { seen.insert($0).inserted }
        return keys.isEmpty ? "" : keys.joined(separator: "\n") + "\n"
    }

    func loadExample() {
        guard !running else { return }
        do {
            // Public upstream known-answer regression, never labelled as a captured user card.
            samples = try ClassicSample.parse("Sec 0 key A cuid 12345678 nt0 1AD8DF2B nr0 1D316024 ar0 620EF048 nt1 30D6CB07 nr1 C52077E2 ar1 837AC61A")
            dictionary = try NFCKeyDictionary(text: "FFFFFFFFFFFF\nA0A1A2A3A4A5\n000000000000\n")
            results = []; error = nil; status = "已载入 Proxmark3 公开测试样本和 3 个候选密钥。"
        } catch { self.error = error.localizedDescription }
    }

    func importFiles(_ urls: [URL], dictionary isDictionary: Bool) {
        guard !running, !urls.isEmpty else { return }
        // Bounds the memory consumed by simultaneous file imports, independent of the picker.
        guard urls.count <= 8 else { error = "一次最多导入 8 个字典文件。"; return }
        running = true; error = nil; status = "正在读取并检查文件…"; fraction = 0
        let currentDictionary = dictionary
        task = Task {
            defer { running = false; task = nil }
            do {
                let input = try await NFCWorkbenchImport.load(urls, dictionary: isDictionary, existing: currentDictionary)
                try Task.checkCancellation()
                if isDictionary { dictionary = input.dictionary } else { samples = input.samples }
                results = []; status = "材料已检查，可以开始离线验证。"
            } catch is CancellationError { status = "已取消导入。" }
            catch { self.error = error.localizedDescription; status = "导入失败，原有材料已保留。" }
        }
    }

    func verify() {
        guard !running, !samples.isEmpty, recoveryMode || dictionary != nil else { return }
        running = true; error = nil; results = []; fraction = 0
        status = recoveryMode ? "正在从离线样本恢复密钥…" : "正在复核候选密钥…"
        let input = samples
        let dictionary = dictionary
        let recover = recoveryMode
        task = Task {
            defer { running = false; task = nil }
            do {
                let update: @Sendable (ClassicProgress) async -> Void = { [weak self] progress in
                    await MainActor.run {
                        self?.fraction = Double(progress.completed) / Double(max(1, progress.total))
                        self?.status = "已命中 \(progress.matchedSamples) 组样本"
                    }
                }
                if recover { results = try await ClassicOffline.recover(samples: input, progress: update) }
                else if let dictionary { results = try await ClassicOffline.verify(samples: input, dictionary: dictionary, progress: update) }
                status = "验证完成：\(results.filter { $0.key != nil }.count)/\(results.count) 组样本命中。"
            } catch is CancellationError { status = "已取消分析。" }
            catch { self.error = error.localizedDescription; status = "分析未完成。" }
        }
    }
    func mergeVerified() {
        guard !running, !verifiedText.isEmpty else { return }
        do {
            let recovered = try NFCKeyDictionary(text: verifiedText)
            dictionary = try NFCKeyDictionary.merge((dictionary.map { [$0] } ?? []) + [recovered])
            status = "已合并并去重，可以导出增强后的字典。"
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { task?.cancel() }
}

private struct NFCWorkbenchImport: Sendable {
    let samples: [ClassicSample]
    let dictionary: NFCKeyDictionary?

    /// Nonisolated async work keeps file parsing and deduplication off the UI executor.
    static func load(_ urls: [URL], dictionary: Bool, existing: NFCKeyDictionary?) async throws -> NFCWorkbenchImport {
        var dictionaries = existing.map { [$0] } ?? []
        var samples: [ClassicSample] = []
        for url in urls {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: NFCKeyDictionary.maxBytes + 1) ?? Data()
            guard bytes.count <= NFCKeyDictionary.maxBytes else { throw RPCError.tooLarge }
            guard let text = String(data: bytes, encoding: .utf8) else { throw RPCError.message("文件不是有效的 UTF-8 文本。") }
            if dictionary { dictionaries.append(try NFCKeyDictionary(text: text)) }
            else { samples = try ClassicSample.parse(text) }
        }
        try Task.checkCancellation()
        return NFCWorkbenchImport(samples: samples, dictionary: dictionary ? try NFCKeyDictionary.merge(dictionaries) : nil)
    }
}
