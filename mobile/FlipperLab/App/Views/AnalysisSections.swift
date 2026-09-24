import SwiftUI
import Charts
import FlipperCore

/// 分析结果 and 包络时序. Facts and notes are the analyser's own wording; the report is
/// produced off the main thread by `RecordDetailView`.
@MainActor struct AnalysisSections: View {
    let report: AnalysisReport?
    let failure: String?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        PixelLabel("分析结果")
        if let report {
            FactList(facts: report.facts, notes: report.notes)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("record.facts")
            if !report.pulseDurations.isEmpty {
                pulseSection(report.pulseDurations)
            }
        } else if let failure {
            ErrorPanel(title: "无法分析", message: failure)
        } else {
            LabPanel {
                ProgressView("正在分析…")
                    .tint(LabColor.ink)
                    .foregroundStyle(LabColor.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func pulseSection(_ durations: [Double]) -> some View {
        PixelLabel("包络时序", meta: "\(durations.count) 个点")
        LabPanel {
            Chart(Array(durations.enumerated()), id: \.offset) { index, duration in
                BarMark(x: .value("顺序", index + 1), y: .value("微秒", duration))
                    .foregroundStyle(duration >= 0 ? LabColor.ink : LabColor.orangeDeep)
            }
            .frame(height: min(chartHeight, 260))
            .accessibilityLabel("脉冲时序图，共 \(durations.count) 个采样间隔，单位微秒")
            HStack(spacing: 16) {
                legendItem("正值", color: LabColor.ink)
                legendItem("负值", color: LabColor.orangeDeep)
            }
            Text("横轴为记录顺序，纵轴为持续时间（微秒）。最多显示 512 个点；数据较多时按区间取代表值，统计仍覆盖全部数据。这是包络时序。")
                .font(.caption)
                .foregroundStyle(LabColor.inkSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record.pulseChart")
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(LabColor.inkSecondary)
        }
    }
}
