import SwiftUI
import FlipperCore

@MainActor struct ToolsView: View {
    let model: AppModel
    var body: some View {
        List {
            Section {
                Label("让手机处理记录，让 Flipper 连接硬件", systemImage: "iphone.and.arrow.forward").font(.headline)
                Text("导入真实采集文件后，在手机本地完成统计、图表、搜索和比较。分析过程不上传云端。")
                    .foregroundStyle(.secondary)
            }
            Section("记录工具") {
                NavigationLink { LibraryView(model: model) } label: { Label("分析与整理记录", systemImage: "waveform.path") }
                NavigationLink { CompareRecordsView(model: model) } label: { Label("比较两次记录", systemImage: "rectangle.split.2x1") }
                NavigationLink { DeviceFilesView(model: model, path: "/ext") } label: { Label("从 Flipper 导入", systemImage: "arrow.down.doc") }
                    .disabled(!model.device.ready || model.busy)
            }
            Section("功能介绍") {
                ForEach(model.guides.prefix(6)) { guide in
                    NavigationLink(guide.title) { GuideDetail(guide: guide) }
                }
            }
            Section("扩展板") {
                Label("等待确认板卡型号", systemImage: "puzzlepiece.extension")
                Text("ESP32 和“WiFi 终结者”需要精确型号、接线与固件版本后才能适配。当前可以导入已保存的文本日志，尚未实现实时串口采集。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("工具")
    }
}

private struct RecordComparison: Sendable {
    let left: AnalysisReport
    let right: AnalysisReport
    let differences: [String]
    let limited: Bool
    static func make(_ a: CaptureRecord, _ b: CaptureRecord) throws -> Self {
        let left = try RecordAnalyzer.analyze(a.rawText, kind: a.kind)
        let right = try RecordAnalyzer.analyze(b.rawText, kind: b.kind)
        // Positional comparison is deliberately bounded; it is not a protocol decoder.
        let aLines = a.rawText.components(separatedBy: .newlines)
        let bLines = b.rawText.components(separatedBy: .newlines)
        let count = min(max(aLines.count, bLines.count), 5_000)
        var differences: [String] = []
        var limited = max(aLines.count, bLines.count) > count
        for index in 0..<count {
            let x = index < aLines.count ? aLines[index] : nil
            let y = index < bLines.count ? bLines[index] : nil
            if x != y {
                if differences.count == 200 { limited = true; break }
                differences.append("第 \(index + 1) 行\nA: \(String((x ?? "[无此行]").prefix(240)))\nB: \(String((y ?? "[无此行]").prefix(240)))")
                if (x?.count ?? 0) > 240 || (y?.count ?? 0) > 240 { limited = true }
            }
        }
        return Self(left: left, right: right, differences: differences, limited: limited)
    }
}

@MainActor struct CompareRecordsView: View {
    let model: AppModel
    @State private var first: UUID?
    @State private var second: UUID?
    @State private var result: RecordComparison?
    @State private var failure: String?
    @State private var comparing = false
    private var selection: String { "\(first?.uuidString ?? ""):\(second?.uuidString ?? "")" }
    var body: some View {
        List {
            Section("选择记录") {
                picker("记录 A", selection: $first)
                picker("记录 B", selection: $second)
                Text("同类型记录更容易比较。文本按相同行号对比；插入一行会影响后续行的对应关系。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if comparing { ProgressView("正在比较…") }
            if let failure { Text(failure).foregroundStyle(.red) }
            if let result {
                Section("记录 A 的统计") {
                    ForEach(Array(result.left.facts.enumerated()), id: \.offset) { _, fact in Text("\(fact.title)：\(fact.value)") }
                }
                Section("记录 B 的统计") {
                    ForEach(Array(result.right.facts.enumerated()), id: \.offset) { _, fact in Text("\(fact.title)：\(fact.value)") }
                }
                Section("按行对比") {
                    if result.differences.isEmpty { Text(result.limited ? "已比较范围内没有差异。" : "两份文本内容相同。") }
                    ForEach(Array(result.differences.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    if result.limited { Text("内容较多，结果已截短。最多比较前 5,000 行、显示 200 处差异，每行预览 240 个字符；可导出完整原文进一步查看。")
                            .font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("比较记录")
        .task(id: selection) {
            result = nil; failure = nil
            guard let a = model.records.first(where: { $0.id == first }),
                  let b = model.records.first(where: { $0.id == second }) else { return }
            comparing = true; defer { comparing = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) { try RecordComparison.make(a, b) }.value
                try Task.checkCancellation(); result = output
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }
    private func picker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("请选择").tag(nil as UUID?)
            ForEach(model.records) { Text($0.name + " · " + $0.kind.title).tag(Optional($0.id)) }
        }
    }
}
