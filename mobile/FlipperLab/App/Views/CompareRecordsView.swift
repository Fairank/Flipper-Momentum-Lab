import SwiftUI
import FlipperCore

// Moved unchanged from the previous ToolsView.swift; only the presentation changed.
private struct RecordComparison: Sendable {
    let left: AnalysisReport
    let right: AnalysisReport
    let differences: [String]
    let limited: Bool
    static func make(_ a: CaptureRecord, _ b: CaptureRecord) throws -> Self {
        let left = try RecordAnalyzer.analyze(a.rawText, kind: a.kind)
        let right = try RecordAnalyzer.analyze(b.rawText, kind: b.kind)
        // Positional comparison is deliberately bounded; it is not a protocol decoder.
        // Stop splitting once the display limit is reached; retain bounded substrings.
        let aLines = a.rawText.split(maxSplits: 5_000, omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        let bLines = b.rawText.split(maxSplits: 5_000, omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
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

/// 比较记录: two record slots, then both statistics and the bounded line-by-line differences (§5.7).
@MainActor struct CompareRecordsView: View {
    let model: AppModel
    @State private var first: UUID?
    @State private var second: UUID?
    @State private var result: RecordComparison?
    @State private var failure: String?
    @State private var comparing = false
    private var selection: String { "\(first?.uuidString ?? ""):\(second?.uuidString ?? "")" }

    var body: some View {
        LabPage {
            slot("记录 A", selection: $first, marker: LabColor.ink, identifier: "compare.pickerA")
            slot("记录 B", selection: $second, marker: LabColor.orangeDeep, identifier: "compare.pickerB")
            Text("同类型记录更容易比较。文本按相同行号对比；插入一行会影响后续行的对应关系。")
                .labFootnote()
            if model.records.isEmpty {
                ReasonNote("先在资料库导入记录，再选择要比较的内容。")
            }
            if comparing {
                LabProgressStrip("正在比较…")
            }
            if let failure {
                ErrorPanel(title: "无法比较", message: failure)
            }
            if let result {
                results(result)
            }
        }
        .labNavigation("比较记录")
        .task(id: selection) {
            result = nil; failure = nil
            comparing = false
            guard let a = model.records.first(where: { $0.id == first }),
                  let b = model.records.first(where: { $0.id == second }) else { return }
            comparing = true
            defer { if !Task.isCancelled { comparing = false } }
            do {
                let output = try await Task.detached(priority: .userInitiated) { try RecordComparison.make(a, b) }.value
                try Task.checkCancellation(); result = output
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }

    private func slot(_ title: String, selection: Binding<UUID?>, marker: Color, identifier: String) -> some View {
        LabPanel(.emphasis, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(marker)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(LabFont.label)
                    .foregroundStyle(LabColor.ink)
            }
            Picker(title, selection: selection) {
                Text("请选择").tag(nil as UUID?)
                ForEach(model.records) { Text($0.name + " · " + $0.kind.title).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(LabColor.ink)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder private func results(_ result: RecordComparison) -> some View {
        PixelLabel("记录 A 的统计")
        FactList(facts: result.left.facts)
        PixelLabel("记录 B 的统计")
        FactList(facts: result.right.facts)
        PixelLabel("按行对比", meta: "\(result.differences.count) 处差异")
        if result.limited {
            ReasonNote("内容较多，结果已截短。最多比较前 5,000 行、显示 200 处差异，每行预览 240 个字符；可导出完整原文进一步查看。")
        }
        if result.differences.isEmpty {
            LabPanel {
                Text(result.limited ? "已比较范围内没有差异。" : "两份文本内容相同。")
                    .font(.body)
                    .foregroundStyle(LabColor.ink)
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(Array(result.differences.enumerated()), id: \.offset) { _, line in
                    DiffBlock(text: line)
                }
            }
        }
    }
}

/// One difference from `RecordComparison`. Only splits the existing "第 N 行 / A: / B:" text
/// for display; anything unexpected is shown verbatim.
private struct DiffBlock: View {
    let text: String

    var body: some View {
        let parts = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        VStack(alignment: .leading, spacing: 6) {
            if parts.count == 3, parts[1].hasPrefix("A: "), parts[2].hasPrefix("B: ") {
                Text(verbatim: String(parts[0]))
                    .font(LabFont.label)
                    .foregroundStyle(LabColor.ink)
                side("A", content: String(parts[1].dropFirst(3)), marker: LabColor.ink, markerText: LabColor.surface)
                side("B", content: String(parts[2].dropFirst(3)), marker: LabColor.orangeDeep, markerText: LabColor.lcdInk)
            } else {
                Text(verbatim: text)
                    .font(LabFont.mono)
                    .foregroundStyle(LabColor.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LabColor.surfaceAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func side(_ label: String, content: String, marker: Color, markerText: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label)
                .font(LabFont.monoCaption.weight(.bold))
                .foregroundStyle(markerText)
                .frame(minWidth: 20, minHeight: 20)
                .background(marker, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(verbatim: content)
                .font(LabFont.mono)
                .foregroundStyle(LabColor.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("记录 \(label)：\(content)")
    }
}
