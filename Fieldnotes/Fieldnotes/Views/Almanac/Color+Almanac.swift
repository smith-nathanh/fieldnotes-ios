import SwiftUI

// MARK: - Almanac color tokens
//
// The "Almanac / Woodcut" palette: rust ink printed on aged paper.
// Defined once here and referenced everywhere — never hardcode a raw hex at a
// call site. See FIELDNOTES_ALMANAC_SPEC.md §1.

extension Color {
    /// App + screen background.
    static let paper = Color(hex: 0xEFE4CF)
    /// Plate/badge fills, inset tiles.
    static let paperCard = Color(hex: 0xE5D5B5)
    /// Photo placeholder / texture base.
    static let paperCardAlt = Color(hex: 0xD9C9A8)

    /// Primary text, rules, dark buttons, tab bar.
    static let ink = Color(hex: 0x2B1D12)
    /// Scientific names, secondary text.
    static let inkSoft = Color(hex: 0x8A6A4A)
    /// Tertiary text under match rows.
    static let inkFaint = Color(hex: 0x9B8768)

    /// Primary accent — eyebrows, counts, primary button, active states.
    static let rust = Color(hex: 0x9E4A26)
    /// Active tab-bar label on the dark ground.
    static let rustSoft = Color(hex: 0xE6A97F)
    /// Secondary accent (rank #2, occasional tags).
    static let olive = Color(hex: 0x7A7433)
    /// Rank #3 chip, disabled.
    static let tan = Color(hex: 0xC8B48F)

    /// Row dividers, list hairlines.
    static let hairline = Color(hex: 0xD6C4A4)
    /// Unselected segmented-control border.
    static let lineWarm = Color(hex: 0xCBB896)
    /// Monospace metadata under counts.
    static let monoLabel = Color(hex: 0xA08C68)

    /// Text on the rust primary button.
    static let buttonInk = Color(hex: 0xF3EAD8)
    /// Mono unit label inside the ink similarity chip.
    static let chipUnit = Color(hex: 0xC9A889)
    /// Inactive segmented-control label text.
    static let segInactive = Color(hex: 0x8A7748)

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
