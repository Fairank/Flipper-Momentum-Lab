import SwiftUI
import FlipperCore

/// Category card for the three-column catalogue grid: an SF Symbol above the Chinese title and
/// the item count. The selected card is orange with #1C1917 content and carries the selected
/// trait; the others use the grouped-row fill with a secondary symbol and count. Text wraps
/// and the card grows with Dynamic Type — nothing shrinks and no height is fixed. A tap only
/// calls `action`; what the selection filters is the caller's decision.
@MainActor struct CatalogCategoryTile: View {
    private let title: String
    private let symbol: String
    private let count: Int
    private let isSelected: Bool
    private let action: () -> Void

    init(title: String, symbol: String, count: Int, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? LabColor.lcdInk : Color.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? LabColor.lcdInk : Color.primary)
                    Text("\(count) 项")
                        .font(.caption)
                        .foregroundStyle(isSelected ? LabColor.lcdInk : Color.secondary)
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 80)
            .background(isSelected ? LabColor.brandOrange : Color(uiColor: .secondarySystemGroupedBackground),
                        in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? LabColor.lcdInk : Color(uiColor: .separator), lineWidth: 1)
            }
            .contentShape(shape)
            // Read as one phrase, "title, N 项". The Button around it stays the element, so the
            // button trait, the action and the selected trait all sit on the same element.
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Catalogue row, display only: a 48 pt symbol tile, the Chinese title and summary, the display
/// category as a caption and the caller's badge in a static capsule. It holds no button and
/// never shows a launch path, an RPC name or any installed, update or connection state of its
/// own. The summary stops at two lines at regular text sizes; at accessibility sizes it is
/// shown in full and the badge moves under the text.
@MainActor struct CatalogAppRow: View {
    private let function: FlipperFunction
    private let badge: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(function: FlipperFunction, badge: String) {
        self.function = function
        self.badge = badge
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            symbolTile
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: function.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(verbatim: function.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    // Left out when the badge already says the same thing.
                    if function.category != badge {
                        Text(verbatim: function.category)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !badge.isEmpty {
                    TagCapsule(text: badge)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 4)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Decorative and fixed at 48 pt, so the text keeps the row's width at large sizes; the
    /// title beside it names the item.
    private var symbolTile: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Image(systemName: function.symbol)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(LabColor.accent)
            .frame(width: 48, height: 48)
            .background(LabColor.orangeSoft, in: shape)
            .overlay {
                shape.strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
