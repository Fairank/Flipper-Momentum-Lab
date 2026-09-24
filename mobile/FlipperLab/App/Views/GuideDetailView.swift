import SwiftUI
import FlipperCore

/// Guide detail: purpose, requirements, numbered steps, the phone / Flipper split,
/// how to read the result and the limits — all catalogue text, unabridged (§5.10).
@MainActor struct GuideDetailView: View {
    let guide: FeatureGuide

    var body: some View {
        LabPage {
            purposeSection
            requirementsSection
            stepsSection
            rolesSection
            resultSection
            limitsSection
        }
        .labNavigation(guide.title)
    }

    @ViewBuilder private var purposeSection: some View {
        PixelLabel("用途")
        LabPanel(.muted) {
            Text(guide.summary)
                .font(.body)
                .foregroundStyle(LabColor.ink)
        }
    }

    @ViewBuilder private var requirementsSection: some View {
        if !guide.requires.isEmpty {
            PixelLabel("准备事项")
            LabPanel {
                ForEach(Array(guide.requires.enumerated()), id: \.offset) { _, text in
                    BulletRow(text: text)
                }
            }
        }
    }

    @ViewBuilder private var stepsSection: some View {
        PixelLabel("操作步骤", meta: "\(guide.steps.count) 步")
        LabPanel {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                StepRow(number: index + 1, text: text)
            }
        }
    }

    /// Two columns normally; stacked at accessibility text sizes.
    @ViewBuilder private var rolesSection: some View {
        PixelLabel("分工")
        AdaptiveStack(verticalAlignment: .top, spacing: 12) {
            roleCard(title: "手机负责", systemImage: "iphone", text: guide.phoneRole, help: nil)
            roleCard(title: "Flipper 负责", systemImage: "dot.radiowaves.left.and.right",
                     text: guide.flipperRole, help: guide.deviceHelp)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var resultSection: some View {
        PixelLabel("怎样理解结果")
        LabPanel {
            Text(guide.result)
                .font(.body)
                .foregroundStyle(LabColor.ink)
        }
    }

    @ViewBuilder private var limitsSection: some View {
        PixelLabel("适用范围", warning: true)
        LabPanel {
            Text(guide.limits)
                .font(.body)
                .foregroundStyle(LabColor.ink)
        }
    }

    private func roleCard(title: String, systemImage: String, text: String, help: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SymbolTile(systemName: systemImage, size: 28)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(LabColor.ink)
            if let help, !help.isEmpty {
                ReasonNote(help)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LabColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LabColor.line, lineWidth: 1))
    }
}
