import SwiftUI
import FlipperCore

/// 工具: three large tool cards, a short guide index and the expansion-board note (§5.3).
@MainActor struct ToolsView: View {
    let model: AppModel

    var body: some View {
        LabPage {
            intro
            PixelLabel("记录工具")
            analyzeCard
            compareCard
            importCard
            guideSection
            expansionSection
        }
        .labNavigation("工具")
    }

    private var intro: some View {
        LabPanel(.muted) {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(systemName: "iphone.and.arrow.forward", size: 40, fill: LabColor.surface)
                VStack(alignment: .leading, spacing: 6) {
                    Text("让手机处理记录，让 Flipper 连接硬件")
                        .font(.headline)
                        .foregroundStyle(LabColor.ink)
                    Text("导入真实采集文件后，在手机本地完成统计、图表、搜索和比较。分析过程不上传云端。")
                        .font(.subheadline)
                        .foregroundStyle(LabColor.inkSecondary)
                }
            }
        }
    }

    private var analyzeCard: some View {
        NavigationLink { LibraryView(model: model) } label: {
            ToolCardLabel(title: "分析与整理记录", subtitle: "统计、图表、搜索，全部在手机本地完成。",
                          systemImage: "waveform.path")
        }
        .buttonStyle(.labCard(emphasis: true))
        .accessibilityLabel("分析与整理记录")
        .accessibilityHint("统计、图表、搜索，全部在手机本地完成。")
        .accessibilityIdentifier("tools.analyze")
    }

    private var compareCard: some View {
        NavigationLink { CompareRecordsView(model: model) } label: {
            ToolCardLabel(title: "比较两次记录", subtitle: "同类型的两条记录按行对比。",
                          systemImage: "rectangle.split.2x1")
        }
        .buttonStyle(.labCard(emphasis: true))
        .accessibilityLabel("比较两次记录")
        .accessibilityHint("同类型的两条记录按行对比。")
        .accessibilityIdentifier("tools.compare")
    }

    private var importCard: some View {
        let reason: String? = !model.device.ready ? "需要先在“设备”页连接 Flipper。"
            : (model.busy ? "有任务正在进行。" : nil)
        return NavigationLink { DeviceFilesView(model: model, path: "/ext") } label: {
            ToolCardLabel(title: "从 Flipper 导入", subtitle: "浏览设备存储，把文件导入资料库。",
                          systemImage: "arrow.down.doc", reason: reason)
        }
        .buttonStyle(.labCard(emphasis: true))
        .disabled(!model.device.ready || model.busy)
        .accessibilityLabel("从 Flipper 导入")
        .accessibilityHint(reason ?? "浏览设备存储，把文件导入资料库。")
        .accessibilityIdentifier("tools.import")
    }

    @ViewBuilder private var guideSection: some View {
        if !model.guides.isEmpty {
            PixelLabel("功能介绍", meta: "前 \(min(model.guides.count, 6)) 篇")
            LabPanel(padded: false) {
                ForEach(Array(model.guides.prefix(6).enumerated()), id: \.element.id) { index, guide in
                    if index > 0 {
                        LabDivider()
                    }
                    NavigationLink { GuideDetailView(guide: guide) } label: {
                        HStack(spacing: 12) {
                            NumberBox(number: index + 1, fill: LabColor.surfaceAlt)
                            Text(verbatim: guide.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            LabChevron()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.labRow)
                    .accessibilityLabel(guide.title)
                    .accessibilityIdentifier("tools.guide.\(guide.id)")
                }
            }
        }
    }

    /// Information only: no action or status is offered until the hardware is confirmed.
    @ViewBuilder private var expansionSection: some View {
        PixelLabel("扩展板")
        LabPanel(.muted) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                Text("待确认硬件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LabColor.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LabColor.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(LabColor.line, lineWidth: 1))
                Text("等待确认板卡型号")
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
            }
            Text("ESP32 和“WiFi 终结者”需要精确型号、接线与固件版本后才能适配。当前可以导入已保存的文本日志，尚未实现实时串口采集。")
                .font(.footnote)
                .foregroundStyle(LabColor.inkSecondary)
        }
    }
}

/// Tool card body: large symbol tile, title, subtitle and — only when disabled — the reason.
private struct ToolCardLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var reason: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SymbolTile(systemName: systemImage, size: 56,
                       fill: isEnabled ? LabColor.orangeSoft : LabColor.surfaceAlt)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? LabColor.ink : LabColor.inkTertiary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(LabColor.inkSecondary)
                if let reason {
                    ReasonNote(reason)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            LabChevron()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }
}
