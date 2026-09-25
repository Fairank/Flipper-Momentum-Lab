import SwiftUI
import FlipperCore

/// 指南: numbered index of the offline guides, searchable by title and summary, followed by
/// the expansion-board note (UI_APPLE_DESIGN.md §4).
@MainActor struct GuidesView: View {
    let model: AppModel
    @State private var search = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Numbers follow the catalogue order, so a guide keeps its number while searching.
    private var matches: [GuideEntry] {
        var result: [GuideEntry] = []
        for (index, guide) in model.guides.enumerated()
        where search.isEmpty || (guide.title + guide.summary).localizedCaseInsensitiveContains(search) {
            result.append(GuideEntry(number: index + 1, guide: guide))
        }
        return result
    }

    var body: some View {
        List {
            if model.guides.isEmpty {
                notLoadedSection
            } else {
                let entries = matches
                Section {
                    if entries.isEmpty {
                        ContentUnavailableView("没有匹配的指南", systemImage: "magnifyingglass",
                                               description: Text("换一个关键词试试。"))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(entries) { entry in
                            guideRow(entry)
                        }
                    }
                } header: {
                    SectionHeader("离线说明", count: "共 \(model.guides.count) 篇")
                }
            }
            if search.isEmpty {
                expansionSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("指南")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索功能")
    }

    private var notLoadedSection: some View {
        Section {
            ContentUnavailableView("指南尚未加载", systemImage: "book.closed")
                .listRowBackground(Color.clear)
            VStack(spacing: 12) {
                Button { Task { await model.load() } } label: {
                    PrimaryButtonLabel(title: "重新加载", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LabColor.brandOrange)
                .disabled(model.busy)
                .accessibilityIdentifier("guides.reload")
                if model.busy {
                    ReasonNote("有任务正在进行。")
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func guideRow(_ entry: GuideEntry) -> some View {
        NavigationLink { GuideDetailView(guide: entry.guide) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: LabFormat.twoDigits(entry.number))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.guide.title)
                        .font(.headline)
                    Text(verbatim: entry.guide.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("\(entry.guide.title)，\(entry.guide.summary)")
        .accessibilityIdentifier("guides.row.\(entry.guide.id)")
    }

    /// Information only: no action or status is offered until the hardware is confirmed.
    private var expansionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TagCapsule(text: "待确认硬件")
                Text("三合一板卡待识别")
                    .font(.headline)
                Text("可导入已保存的 Wi-Fi 扫描记录，在手机查看多个网络及信道分布。ESP32、CC1101 和你称作 nrf244 的三合一板仍需确认芯片、接线与固件；实时串口采集尚未适配。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            SectionHeader("扩展板")
        }
    }
}

private struct GuideEntry: Identifiable {
    let number: Int
    let guide: FeatureGuide
    var id: String { guide.id }
}
