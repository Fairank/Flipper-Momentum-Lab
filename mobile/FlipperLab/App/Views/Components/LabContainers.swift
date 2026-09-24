import SwiftUI

/// Scrolling page used by every screen. The warm background also fills the safe areas
/// under the navigation and tab bars, so no default white strip shows below the content.
struct LabPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(LabColor.bg.ignoresSafeArea())
    }
}

enum LabPanelStyle {
    case neutral, emphasis, danger, muted
}

/// Panel container (§2.3): 14 pt corners, border instead of shadow.
struct LabPanel<Content: View>: View {
    private let style: LabPanelStyle
    private let padded: Bool
    private let spacing: CGFloat
    private let content: Content

    init(_ style: LabPanelStyle = .neutral, padded: Bool = true, spacing: CGFloat = 12,
         @ViewBuilder content: () -> Content) {
        self.style = style
        self.padded = padded
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: padded ? spacing : 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style == .muted ? LabColor.surfaceAlt : LabColor.surface, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(border, lineWidth: borderWidth))
    }

    private var padding: CGFloat {
        guard padded else { return 0 }
        return style == .muted ? 12 : 16
    }

    private var border: Color {
        switch style {
        case .neutral: return LabColor.line
        case .emphasis: return LabColor.strongLine
        case .danger: return LabColor.danger
        case .muted: return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .neutral: return 1
        case .emphasis, .danger: return 1.5
        case .muted: return 0
        }
    }
}

/// Section label: 6 pt orange pixel, caption title (a real header text) and optional meta.
struct PixelLabel: View {
    private let title: String
    private let meta: String?
    private let warning: Bool
    private let spaced: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, meta: String? = nil, warning: Bool = false, spaced: Bool = true) {
        self.title = title
        self.meta = meta
        self.warning = warning
        self.spaced = spaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rectangle()
                .fill(LabColor.orange)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] }
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    metaText
                }
            } else {
                titleText
                Spacer(minLength: 8)
                metaText
            }
        }
        // 24 pt above a group, 8 pt to its panel (§2.3).
        .padding(.top, spaced ? 12 : 0)
        .padding(.bottom, spaced ? -4 : 0)
    }

    private var titleText: some View {
        Text(title)
            .font(LabFont.label)
            .foregroundStyle(warning ? LabColor.warnText : LabColor.ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var metaText: some View {
        if let meta {
            Text(meta)
                .font(LabFont.monoCaption)
                .foregroundStyle(LabColor.inkSecondary)
        }
    }
}

/// Pixel pointer plus a concrete sentence: why a control is disabled, or a note from the analyser.
struct ReasonNote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PixelBitmapView(bitmap: PixelSprites.pointer, unit: 2, color: LabColor.orangeDeep)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] }
            Text(text)
                .font(.footnote)
                .foregroundStyle(LabColor.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LabDivider: View {
    var body: some View {
        Rectangle()
            .fill(LabColor.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct LabChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(LabColor.inkTertiary)
            .accessibilityHidden(true)
    }
}

/// Non-interactive activity strip. It shows an indeterminate spinner only — never a percentage.
struct LabProgressStrip: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(LabColor.ink)
            Text(title)
                .font(.headline)
                .foregroundStyle(LabColor.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(LabColor.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Error panel (§7): 1.5 pt danger border, danger title, selectable message, optional actions.
struct ErrorPanel<Actions: View>: View {
    private let title: String
    private let message: String
    private let actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        LabPanel(.danger) {
            Text(title)
                .font(.headline)
                .foregroundStyle(LabColor.dangerText)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(LabColor.ink)
                .textSelection(.enabled)
            actions
        }
    }
}

extension ErrorPanel where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

/// Empty state: pixel tray, title, explanation and an optional action (§7).
struct EmptyPanel<Action: View>: View {
    private let title: String
    private let message: String?
    private let showsTray: Bool
    private let action: Action

    init(_ title: String, message: String? = nil, showsTray: Bool = true, @ViewBuilder action: () -> Action) {
        self.title = title
        self.message = message
        self.showsTray = showsTray
        self.action = action()
    }

    var body: some View {
        LabPanel {
            VStack(spacing: 12) {
                if showsTray {
                    PixelBitmapView(bitmap: PixelSprites.tray, unit: 4, color: LabColor.inkSecondary)
                        .padding(.vertical, 4)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(LabColor.ink)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(LabColor.inkSecondary)
                }
                action
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

extension EmptyPanel where Action == EmptyView {
    init(_ title: String, message: String? = nil, showsTray: Bool = true) {
        self.init(title, message: message, showsTray: showsTray) { EmptyView() }
    }
}

/// Horizontal at normal sizes, vertical at accessibility text sizes: Chinese text wraps
/// onto its own lines instead of shrinking.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let horizontalAlignment: HorizontalAlignment
    private let verticalAlignment: VerticalAlignment
    private let spacing: CGFloat
    private let content: Content

    init(horizontalAlignment: HorizontalAlignment = .leading, verticalAlignment: VerticalAlignment = .center,
         spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout {
            content
        }
    }
}

/// Wrapping row layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), frames)
    }
}
