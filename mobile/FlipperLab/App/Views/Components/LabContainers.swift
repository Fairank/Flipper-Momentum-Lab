import SwiftUI

/// Why a control is disabled, or a caveat next to it: an info symbol that scales with the
/// footnote text. One accessibility element whose label is exactly the sentence.
struct ReasonNote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Activity row with an indeterminate spinner only — never a percentage.
struct BusyRow: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Error row: red warning symbol with the title, the selectable message, then optional actions.
struct ErrorRow<Actions: View>: View {
    private let title: String
    private let message: String
    private let actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            Text(message)
                .textSelection(.enabled)
            actions
        }
        .padding(.vertical, 4)
    }
}

extension ErrorRow where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

/// List section header with an optional count. Text keeps its case (paths, "Flipper"), and
/// the count moves under the title at accessibility text sizes instead of truncating.
struct SectionHeader: View {
    private let title: String
    private let count: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, count: String? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        Group {
            if let count, dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(count).monospacedDigit()
                }
            } else if let count {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                    Spacer(minLength: 8)
                    Text(count).monospacedDigit()
                }
            } else {
                Text(title)
            }
        }
        .textCase(nil)
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

/// Wrapping row layout for tag capsules.
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
