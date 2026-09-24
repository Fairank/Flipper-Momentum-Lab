import SwiftUI
import UIKit

/// Warm case / ink / orange / LCD palette (UI_REDESIGN.md §2.1).
/// Dynamic colours resolve from the trait collection, so the app always follows the
/// system appearance unless a DEBUG UI-test launch argument overrides it.
enum LabColor {
    static let bg = dynamic(0xF4EFE6, 0x131110)
    static let surface = dynamic(0xFFFCF7, 0x1E1B18)
    static let surfaceAlt = dynamic(0xEFE8DC, 0x26221E)
    static let ink = dynamic(0x1C1917, 0xF2ECE3)
    static let inkSecondary = dynamic(0x57534E, 0xBDB4A8)
    static let inkTertiary = dynamic(0x6B6560, 0x9A9188)
    static let line = dynamic(0xD6CEC2, 0x3A342E)
    /// Emphasis panels and the device body: ink in light mode, softer in dark mode.
    static let strongLine = dynamic(0x1C1917, 0xBDB4A8)
    static let orange = dynamic(0xFF8200, 0xFF8C1A)
    static let orangeDeep = dynamic(0xD96A00, 0xE07400)
    /// Legible system control text on light material; warm amber in dark mode.
    static let controlTint = dynamic(0x994500, 0xFFB566)
    static let orangeSoft = dynamic(0xFFE3C2, 0x4A2C0F)
    static let ok = dynamic(0x2E7D32, 0x6FCF7A)
    static let okBg = dynamic(0xDCEFD9, 0x1F3B22)
    static let okText = dynamic(0x1F5E24, 0x9BD9A3)
    static let danger = dynamic(0xB42318, 0xF0716A)
    static let dangerBg = dynamic(0xF9DCD9, 0x4A1F1B)
    static let dangerText = dynamic(0x8E1B12, 0xF5A199)
    static let warnText = dynamic(0x8A4B00, 0xFFB566)
    static let tabBar = dynamic(0x1C1917, 0x131110)
    /// LCD pixels, the LCD bezel and text on orange fills: the same in light and dark mode.
    static let lcdInk = Color(uiColor: UIColor(labHex: 0x1C1917))

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        let lightColor = UIColor(labHex: light)
        let darkColor = UIColor(labHex: dark)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

private extension UIColor {
    convenience init(labHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Type roles (§2.2). Chinese text always uses system text styles so Dynamic Type applies.
enum LabFont {
    /// Paths, RSSI, sizes, times and difference lines.
    static let mono = Font.system(.footnote, design: .monospaced)
    /// Card metadata, counts and guide numbers.
    static let monoCaption = Font.system(.caption, design: .monospaced)
    /// Pixel labels above panels.
    static let label = Font.caption.weight(.semibold)

    /// LCD tokens only. A fixed size keeps the device art in proportion; the LCD is hidden
    /// from VoiceOver and the same state is written in real text beside it.
    static func lcd(_ px: CGFloat) -> Font {
        .system(size: max(10, px * 4), weight: .bold, design: .monospaced)
    }
}

enum LabFormat {
    /// "01", "02" … for steps, guides and infrared keys.
    static func twoDigits(_ number: Int) -> String {
        (0..<10).contains(number) ? "0\(number)" : "\(number)"
    }
}

extension View {
    /// Inline title over a solid warm bar that matches the page background (§3).
    func labNavigation(_ title: String) -> some View {
        navigationTitle(title)
            .tint(LabColor.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LabColor.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// iOS 26 owns the glass background and its contrasting labels. Older systems use ink.
    @ViewBuilder func labTabChrome() -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            toolbarBackground(LabColor.tabBar, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
        }
    }
}

extension Text {
    /// Footnote for limits and disclaimers, placed next to the action it qualifies.
    func labFootnote() -> some View {
        font(.footnote).foregroundStyle(LabColor.inkTertiary)
    }
}
