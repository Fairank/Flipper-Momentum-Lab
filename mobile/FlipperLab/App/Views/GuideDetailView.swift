import SwiftUI
import FlipperCore

/// Guide detail as a grouped reading list: purpose, requirements, numbered steps, the phone /
/// Flipper split, how to read the result and the limits — all catalogue text, unabridged and
/// selectable (UI_APPLE_DESIGN.md §4).
@MainActor struct GuideDetailView: View {
    let guide: FeatureGuide

    var body: some View {
        List {
            Section {
                Text(guide.summary)
            } header: {
                SectionHeader("用途")
            }
            if !guide.requires.isEmpty {
                Section {
                    ForEach(Array(guide.requires.enumerated()), id: \.offset) { _, text in
                        Text(text)
                    }
                } header: {
                    SectionHeader("准备事项")
                }
            }
            Section {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                    StepRow(number: index + 1, text: text)
                }
            } header: {
                SectionHeader("操作步骤", count: "\(guide.steps.count) 步")
            }
            Section {
                roleRow(title: "手机负责", systemImage: "iphone", text: guide.phoneRole)
                roleRow(title: "Flipper 负责", systemImage: "dot.radiowaves.left.and.right", text: guide.flipperRole)
            } header: {
                SectionHeader("分工")
            } footer: {
                if !guide.deviceHelp.isEmpty {
                    Text(guide.deviceHelp)
                }
            }
            Section {
                Text(guide.result)
            } header: {
                SectionHeader("怎样理解结果")
            }
            Section {
                Text(guide.limits)
            } header: {
                SectionHeader("适用范围")
            }
        }
        .listStyle(.insetGrouped)
        .textSelection(.enabled)
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Stacked role rows: full-width Chinese prose instead of two narrow columns.
    private func roleRow(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(text)
        }
        .padding(.vertical, 4)
    }
}
