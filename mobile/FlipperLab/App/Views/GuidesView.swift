import SwiftUI
import FlipperCore

/// 功能指南: numbered index of the offline guides, searchable by title and summary (§5.9).
@MainActor struct GuidesView: View {
    let model: AppModel
    @State private var search = ""

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
        LabPage {
            if model.guides.isEmpty {
                EmptyPanel("指南尚未加载") {
                    Button("重新加载") { Task { await model.load() } }
                        .buttonStyle(.labPrimary)
                        .disabled(model.busy)
                        .accessibilityIdentifier("guides.reload")
                    if model.busy {
                        ReasonNote("有任务正在进行。")
                    }
                }
            } else {
                let entries = matches
                PixelLabel("离线说明", meta: "共 \(model.guides.count) 篇")
                if entries.isEmpty {
                    EmptyPanel("没有匹配的指南", message: "换一个关键词试试。", showsTray: false)
                } else {
                    LabPanel(padded: false) {
                        ForEach(entries) { entry in
                            if entry.number != entries.first?.number {
                                LabDivider()
                            }
                            guideRow(entry)
                        }
                    }
                }
            }
        }
        .labNavigation("功能指南")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索功能")
    }

    private func guideRow(_ entry: GuideEntry) -> some View {
        NavigationLink { GuideDetailView(guide: entry.guide) } label: {
            HStack(alignment: .top, spacing: 14) {
                NumberBox(number: entry.number, size: 32, fill: LabColor.surfaceAlt)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.guide.title)
                        .font(.headline)
                        .foregroundStyle(LabColor.ink)
                    Text(verbatim: entry.guide.summary)
                        .font(.subheadline)
                        .foregroundStyle(LabColor.inkSecondary)
                        .lineLimit(3)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                LabChevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.labRow)
        .accessibilityLabel("\(entry.guide.title)，\(entry.guide.summary)")
        .accessibilityIdentifier("guides.row.\(entry.guide.id)")
    }
}

private struct GuideEntry: Identifiable {
    let number: Int
    let guide: FeatureGuide
    var id: String { guide.id }
}
