import CoreText
import Foundation

/// Registers the bundled Almanac font faces with CoreText at launch, so
/// `Font.custom(_:size:)` can resolve them by PostScript name. Done in code
/// rather than via `UIAppFonts` because the app uses an auto-generated
/// Info.plist (array keys aren't reliably injectable there).
enum AlmanacFonts {
    /// PostScript names of the bundled TTFs (see Resources/Fonts).
    static let faceNames = [
        "Newsreader-Regular",
        "Newsreader-SemiBold",
        "Newsreader-Bold",
        "Newsreader-Italic",
        "IBMPlexMono-Regular",
        "IBMPlexMono-Medium",
    ]

    static func registerAll() {
        for name in faceNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // A duplicate-registration error on a warm relaunch is benign.
        }
    }
}
