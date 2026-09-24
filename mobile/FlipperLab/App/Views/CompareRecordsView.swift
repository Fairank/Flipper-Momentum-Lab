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

/// 比较记录: two record slots, then both statistics and the bounded line-by-line differences
/// (UI_APPLE_DESIGN.md §4). Opened from a record's menu, that record is already chosen as A.
@MainActor struct CompareRecordsView: View {
    let model: AppModel
    @State private var first: UUID?
    @State private var second: UUID?
    @State private var result: RecordComparison?
    @State private var failure: String?
    @State private var comparing = false
    private var selection: String { "\(first?.uuidString ?? ""):\(second?.uuidString ?? "")" }

    init(model: AppModel, initialFirst: UUID? = nil) {
        self.model = model
        _first = State(initialValue: initialFirst)
    }

    var body: some View {
        Form {
            Section {
                slot("记录 A", selection: $first, identifier: "compare.pickerA")
                slot("记录 B", selection: $second, identifier: "compare.pickerB")
                if model.records.isEmpty {
                    ReasonNote("先在资料库导入记录，再选择要比较的内容。")
                }
            } header: {
                SectionHeader("选择记录")
            } footer: {
                Text("同类型记录更容易比较。文本按相同行号对比；插入一行会影响后续行的对应关系。")
            }
            if comparing {
                Section {
                    BusyRow("正在比较…")
                }
            }
            if let failure {
                Section {
                    ErrorRow(title: "无法比较", message: failure)
                }
            }
            if let result {
                results(result)
            }
        }
        .navigationTitle("比较记录")
        .navigationBarTitleDisplayMode(.inline)
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

    /// A 44 pt row whose label wraps the full record name; the menu inside is a checkmarked picker.
    private func slot(_ title: String, selection: Binding<UUID?>, identifier: String) -> some View {
        let chosen = model.records.first { $0.id == selection.wrappedValue }
        let value = chosen.map { $0.name + " · " + $0.kind.title } ?? "请选择"
        return Menu {
            Picker(title, selection: selection) {
                Text("请选择").tag(nil as UUID?)
                ForEach(model.records) { Text($0.name + " · " + $0.kind.title).tag(Optional($0.id)) }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    Text(verbatim: value)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func results(_ result: RecordComparison) -> some View {
        Section {
            FactList(facts: result.left.facts)
        } header: {
            SectionHeader("记录 A 的统计")
        }
        Section {
            FactList(facts: result.right.facts)
        } header: {
            SectionHeader("记录 B 的统计")
        }
        Section {
            // The caveat qualifies the list below it, so it leads the section.
            if result.limited {
                ReasonNote("内容较多，结果已截短。最多比较前 5,000 行、显示 200 处差异，每行预览 240 个字符；可导出完整原文进一步查看。")
            }
            if result.differences.isEmpty {
                Text(result.limited ? "已比较范围内没有差异。" : "两份文本内容相同。")
            } else {
                ForEach(Array(result.differences.enumerated()), id: \.offset) { _, line in
                    DiffBlock(text: line)
                }
            }
        } header: {
            SectionHeader("按行对比", count: "\(result.differences.count) 处差异")
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
                    .font(.subheadline.weight(.semibold))
                side("A", content: String(parts[1].dropFirst(3)),
                     marker: Color.primary, markerText: Color(uiColor: .systemBackground))
                side("B", content: String(parts[2].dropFirst(3)),
                     marker: LabColor.brandOrange, markerText: LabColor.lcdInk)
            } else {
                Text(verbatim: text)
                    .font(LabFont.mono)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func side(_ label: String, content: String, marker: Color, markerText: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label)
                .font(LabFont.monoCaption.weight(.bold))
                .foregroundStyle(markerText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(marker, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(verbatim: content)
                .font(LabFont.mono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("记录 \(label)：\(content)")
    }
}
