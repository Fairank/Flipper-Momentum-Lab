import SwiftUI

// Button styles from UI_REDESIGN.md §9. Every style keeps its minimum height at any
// Dynamic Type size and draws a real disabled state (colour and border change, not opacity).

/// Orange 52 pt main action. Text on orange is always #1C1917.
struct LabPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? LabColor.lcdInk : LabColor.inkTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(isEnabled ? LabColor.orangeDeep : LabColor.line, lineWidth: 1))
                .contentShape(shape)
        }

        private var fill: Color {
            guard isEnabled else { return LabColor.surfaceAlt }
            return configuration.isPressed ? LabColor.orangeDeep : LabColor.orange
        }
    }
}

/// Outlined actions: secondary (48 pt), destructive (48 pt) and compact inline (44 pt).
struct LabOutlineButtonStyle: ButtonStyle {
    enum Variant { case secondary, destructive, compact }
    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        OutlineBody(configuration: configuration, variant: variant)
    }

    private struct OutlineBody: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let compact = variant == .compact
            let shape = RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
            let font: Font = compact ? Font.subheadline.weight(.semibold) : Font.headline
            let maxWidth: CGFloat? = compact ? nil : .infinity
            configuration.label
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundStyle(textColor)
                .padding(.horizontal, compact ? 14 : 16)
                .padding(.vertical, compact ? 8 : 12)
                .frame(maxWidth: maxWidth, minHeight: compact ? 44 : 48)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: compact ? 1 : 1.5))
                .contentShape(shape)
        }

        private var textColor: Color {
            guard isEnabled else { return LabColor.inkTertiary }
            return variant == .destructive ? LabColor.danger : LabColor.ink
        }

        private var fill: Color {
            guard isEnabled, configuration.isPressed else { return LabColor.surface }
            return variant == .destructive ? LabColor.dangerBg : LabColor.surfaceAlt
        }

        private var borderColor: Color {
            guard isEnabled else { return LabColor.line }
            return variant == .destructive ? LabColor.danger : LabColor.strongLine
        }
    }
}

/// Physical-looking infrared key: 56 pt face over a 3 pt ink edge that shrinks to 1 pt
/// when pressed. With Reduce Motion only the face colour changes.
struct LabKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration)
    }

    private struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            let pressed = isEnabled && configuration.isPressed
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isEnabled ? LabColor.ink : LabColor.inkTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(pressed ? LabColor.surfaceAlt : LabColor.surface, in: shape)
                .overlay(shape.strokeBorder(isEnabled ? LabColor.strongLine : LabColor.line, lineWidth: 1.5))
                .offset(y: pressed && !reduceMotion ? 2 : 0)
                .background(alignment: .top) {
                    if isEnabled {
                        shape.fill(LabColor.strongLine).offset(y: 3)
                    }
                }
                .padding(.bottom, isEnabled ? 3 : 0)
                .contentShape(shape)
        }
    }
}

/// Whole-card navigation (tool cards, record cards).
struct LabCardButtonStyle: ButtonStyle {
    var emphasis = false

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, emphasis: emphasis)
    }

    private struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        let emphasis: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            let strong = emphasis && isEnabled
            configuration.label
                .foregroundStyle(isEnabled ? LabColor.ink : LabColor.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(configuration.isPressed ? LabColor.surfaceAlt : LabColor.surface, in: shape)
                .overlay(shape.strokeBorder(strong ? LabColor.strongLine : LabColor.line, lineWidth: strong ? 1.5 : 1))
                .contentShape(shape)
        }
    }
}

/// Row inside a panel (nearby devices, folders, guides). At least 44 pt tall.
struct LabRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? LabColor.ink : LabColor.inkTertiary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(configuration.isPressed ? LabColor.surfaceAlt : Color.clear)
                .contentShape(Rectangle())
        }
    }
}

/// 44 pt filter chip; the selected chip is orange with #1C1917 text.
struct LabChipButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let fill: Color = selected ? LabColor.orange : (configuration.isPressed ? LabColor.surfaceAlt : LabColor.surface)
        return configuration.label
            .font(selected ? Font.subheadline.weight(.semibold) : Font.subheadline)
            .foregroundStyle(selected ? LabColor.lcdInk : LabColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(selected ? LabColor.orangeDeep : LabColor.line, lineWidth: 1))
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == LabPrimaryButtonStyle {
    static var labPrimary: LabPrimaryButtonStyle { LabPrimaryButtonStyle() }
}

extension ButtonStyle where Self == LabOutlineButtonStyle {
    static var labSecondary: LabOutlineButtonStyle { LabOutlineButtonStyle(variant: .secondary) }
    static var labDestructive: LabOutlineButtonStyle { LabOutlineButtonStyle(variant: .destructive) }
    static var labCompact: LabOutlineButtonStyle { LabOutlineButtonStyle(variant: .compact) }
}

extension ButtonStyle where Self == LabKeyButtonStyle {
    static var labKey: LabKeyButtonStyle { LabKeyButtonStyle() }
}

extension ButtonStyle where Self == LabCardButtonStyle {
    static func labCard(emphasis: Bool = false) -> LabCardButtonStyle { LabCardButtonStyle(emphasis: emphasis) }
}

extension ButtonStyle where Self == LabRowButtonStyle {
    static var labRow: LabRowButtonStyle { LabRowButtonStyle() }
}
