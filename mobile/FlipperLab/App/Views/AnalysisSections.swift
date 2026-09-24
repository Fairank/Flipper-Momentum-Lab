import SwiftUI
import Charts
import FlipperCore

/// 分析结果 and 包络时序 as list sections. Facts and notes are the analyser's own wording;
/// the report is produced off the main thread by `RecordDetailView`. The chart keeps its
/// linear scale, signed durations and data exactly as the analyser returns them.
@MainActor struct AnalysisSections: View {
    let report: AnalysisReport?
    let failure: String?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        Section {
            if let report {
                if !report.facts.isEmpty {
                    FactList(facts: report.facts)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("record.facts")
                }
            } else if let failure {
                ErrorRow(title: "无法分析", message: failure)
            } else {
                BusyRow("正在分析…")
            }
        } header: {
            SectionHeader("分析结果")
        } footer: {
            if let report, !report.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                    }
                }
            }
        }
        if let report, !report.pulseDurations.isEmpty {
            pulseSection(report.pulseDurations)
        }
    }

    private func pulseSection(_ durations: [Double]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Chart(Array(durations.enumerated()), id: \.offset) { index, duration in
                    BarMark(x: .value("顺序", index + 1), y: .value("微秒", duration))
                        .foregroundStyle(duration >= 0 ? Color.primary : LabColor.accent)
                }
                .frame(height: min(chartHeight, 260))
                .accessibilityLabel("脉冲时序图，共 \(durations.count) 个采样间隔，单位微秒")
                HStack(spacing: 16) {
                    legendItem("正值", color: .primary)
                    legendItem("负值", color: LabColor.accent)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("record.pulseChart")
        } header: {
            SectionHeader("包络时序", count: "\(durations.count) 个点")
        } footer: {
            Text("横轴为记录顺序，纵轴为持续时间（微秒）。最多显示 512 个点；数据较多时按区间取代表值，统计仍覆盖全部数据。")
        }
    }

    /// Legend swatch as an SF Symbol, so it scales with the caption beside it.
    private func legendItem(_ title: String, color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "square.fill")
                .foregroundStyle(color)
        }
        .font(.caption)
    }
}
