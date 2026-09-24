import SwiftUI

/// One inked cell of a pixel bitmap.
struct PixelCell: Hashable, Sendable {
    let x: Int
    let y: Int
}

/// A 1-bit bitmap drawn from square cells. Rows use '#' for ink and '.' for empty.
/// The width is the widest row, so a short row can only leave cells empty; it cannot
/// trap or shift the drawing.
struct PixelBitmap: Sendable {
    let width: Int
    let height: Int
    let cells: [PixelCell]

    init(rows: [String]) {
        var cells: [PixelCell] = []
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character == "#" {
                cells.append(PixelCell(x: x, y: y))
            }
        }
        self.init(width: rows.map(\.count).max() ?? 0, height: rows.count, cells: cells)
    }

    init(width: Int, height: Int, cells: [PixelCell]) {
        self.width = width
        self.height = height
        self.cells = cells
    }
}

/// All cells as one path, filled like any SwiftUI shape so dynamic colours resolve normally.
struct PixelShape: Shape {
    let bitmap: PixelBitmap

    func path(in rect: CGRect) -> Path {
        guard bitmap.width > 0, bitmap.height > 0 else { return Path() }
        let unit = min(rect.width / CGFloat(bitmap.width), rect.height / CGFloat(bitmap.height))
        var path = Path()
        for cell in bitmap.cells {
            path.addRect(CGRect(x: rect.minX + CGFloat(cell.x) * unit,
                                y: rect.minY + CGFloat(cell.y) * unit,
                                width: unit, height: unit))
        }
        return path
    }
}

/// Decorative pixel art at a whole-point cell size. Always hidden from VoiceOver:
/// anything it shows is also stated in real text nearby.
struct PixelBitmapView: View {
    let bitmap: PixelBitmap
    let unit: CGFloat
    let color: Color

    var body: some View {
        PixelShape(bitmap: bitmap)
            .fill(color)
            .frame(width: CGFloat(bitmap.width) * unit, height: CGFloat(bitmap.height) * unit)
            .accessibilityHidden(true)
    }
}

/// Original sprites for this app (UI_REDESIGN.md §4.5). Not taken from any official artwork.
enum PixelSprites {
    // Dolphin, 32 × 16, facing right: tail flukes on the left, dorsal fin on top, beak on
    // the right. Each row is four 8-cell blocks; the eye is the gap at x 24–25 on rows 6–7.
    private static let dolphinBlocks: [[String]] = [
        ["........", "........", "........", "........"],
        ["........", ".....##.", "........", "........"],
        ["........", ".....###", "#.......", "........"],
        ["........", "......##", "####....", "........"],
        ["##......", "......##", "#####...", "........"],
        [".##.....", "..######", "########", "#......."],
        ["..##...#", "########", "########", "..##...."],
        ["...#####", "########", "########", "..###..."],
        ["....####", "########", "########", "########"],
        ["...#####", "########", "########", "#######."],
        ["..##...#", "########", "########", "####...."],
        [".##.....", "..######", "########", "#......."],
        ["##......", "......##", "#####...", "........"],
        ["........", ".......#", "##......", "........"],
        ["........", "......##", "........", "........"],
        ["........", "........", "........", "........"],
    ]

    static let dolphinOpen = blocks(dolphinBlocks)

    /// Blink and "Bluetooth unavailable": only row 6 changes, so the eye becomes a closed line.
    static let dolphinClosed: PixelBitmap = {
        var rows = PixelSprites.dolphinBlocks
        rows[6] = ["..##...#", "########", "########", "####...."]
        return PixelSprites.blocks(rows)
    }()

    /// Signal arcs, 7 × 7 each; animation frame n draws the first n arcs.
    static let arcs: [PixelBitmap] = [
        cells(7, 7, [(0, 2), (1, 3), (0, 4)]),
        cells(7, 7, [(2, 1), (3, 2), (3, 3), (3, 4), (2, 5)]),
        cells(7, 7, [(4, 0), (5, 1), (6, 2), (6, 3), (6, 4), (5, 5), (4, 6)]),
    ]

    /// Sleep mark "Z", 3 × 3, shown only while Bluetooth is unavailable.
    static let sleep = cells(3, 3, [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)])

    /// Reason pointer "▸", 3 × 5.
    static let pointer = cells(3, 5, [(0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2), (0, 3), (1, 3), (0, 4)])

    /// Empty-state tray, 16 × 7.
    static let tray = blocks([
        ["#.......", ".......#"],
        ["#.......", ".......#"],
        ["#.......", ".......#"],
        ["#.......", ".......#"],
        ["#....###", "###....#"],
        ["#...#...", "...#...#"],
        ["########", "########"],
    ])

    private static func blocks(_ rows: [[String]]) -> PixelBitmap {
        PixelBitmap(rows: rows.map { $0.joined() })
    }

    private static func cells(_ width: Int, _ height: Int, _ points: [(Int, Int)]) -> PixelBitmap {
        PixelBitmap(width: width, height: height, cells: points.map { PixelCell(x: $0.0, y: $0.1) })
    }
}
