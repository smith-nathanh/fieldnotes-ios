import SwiftUI

// MARK: - Almanac type ramp
//
// Two families per the spec (§2): an editorial serif for everything readable,
// and a mono for labels/eyebrows/metadata.
//
// Fonts are served by the bundled **Newsreader** (serif) and **IBM Plex Mono**
// (mono) faces, registered at launch by `AlmanacFonts.registerAll()`. The faces
// are pre-weighted static instances, so we select a face by weight rather than
// applying `.weight()` to a single variable face. Set `useBundledFonts` to
// `false` to fall back to the system serif/monospaced stand-ins.

private let useBundledFonts = false

extension Font {
    /// Editorial serif — display, body, and all numerals.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard useBundledFonts else {
            return .system(size: size, weight: weight, design: .serif)
        }
        let face: String
        switch weight {
        case .bold, .heavy, .black:
            face = "Newsreader-Bold"
        case .semibold, .medium:
            face = "Newsreader-SemiBold"
        default:
            face = "Newsreader-Regular"
        }
        return .custom(face, size: size)
    }

    /// Serif italic — used only for scientific names (regular weight).
    static func serifItalic(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard useBundledFonts else {
            return .system(size: size, weight: weight, design: .serif).italic()
        }
        return .custom("Newsreader-Italic", size: size)
    }

    /// Monospace — labels, eyebrows, metadata, tags. Always uppercase + tracked.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        guard useBundledFonts else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let face = weight == .regular ? "IBMPlexMono-Regular" : "IBMPlexMono-Medium"
        return .custom(face, size: size)
    }
}

extension CGFloat {
    /// Convert an em-based tracking value to points for a given font size,
    /// matching the CSS `letter-spacing` figures in the spec.
    static func tracking(_ em: CGFloat, at size: CGFloat) -> CGFloat {
        em * size
    }
}
