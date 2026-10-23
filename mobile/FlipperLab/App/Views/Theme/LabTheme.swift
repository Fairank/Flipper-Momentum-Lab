import SwiftUI
import UIKit

/// Brand tokens kept on top of the system palette (UI_APPLE_DESIGN.md §3). Pages, rows, text
/// and separators use semantic system colours, so the app follows the system appearance
/// unless a DEBUG UI-test launch argument overrides it.
enum LabColor {
    /// Flipper orange: the LCD, primary button fills, the selected filter and the running task.
    static let brandOrange = dynamic(0xFF8200, 0xFF8C1A)
    /// App tint. Dark enough on light glass for legible tab and toolbar labels; amber in dark mode.
    static let accent = dynamic(0x994500, 0xFFB566)
    /// Soft fill behind SF Symbol tiles.
    static let orangeSoft = dynamic(0xFFE3C2, 0x4A2C0F)
    /// Text on any orange fill, the LCD pixels and its bezel: the same in light and dark mode.
    /// White on #FF8200 is only about 2.5:1, so it is never used on orange.
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

/// Monospaced text is only for paths, RSSI, sizes, device keys, raw content and difference
/// lines — never for Chinese or dates. Everything else uses system text styles.
enum LabFont {
    /// Paths, RSSI, sizes, device keys and difference lines.
    static let mono = Font.system(.footnote, design: .monospaced)
    /// Raw file preview and the A / B difference markers.
    static let monoCaption = Font.system(.caption, design: .monospaced)

    /// LCD tokens only. A fixed size keeps the pixel art in proportion; the LCD is hidden
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
