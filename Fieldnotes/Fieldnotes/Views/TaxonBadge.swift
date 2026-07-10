import FieldnotesCore
import SwiftUI

/// Bordered plate holding a line-drawn animal glyph in ink (§4 plate badge).
struct TaxonBadge: View {
    var taxon: Taxon
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.36, weight: .regular))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.paperCard))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1.5))
            .accessibilityLabel(taxon.rawValue.capitalized)
    }

    private var iconName: String {
        switch taxon {
        case .bird:
            return "bird"
        case .mammal:
            return "hare"
        case .amphibian:
            return "drop"
        case .reptile:
            return "lizard"
        case .fish:
            return "fish"
        case .insect:
            return "ant"
        case .arachnid:
            return "ant"
        case .crustacean:
            return "water.waves"
        case .mollusk:
            return "circle.dotted"
        case .animal:
            return "pawprint"
        case .unknown:
            return "questionmark"
        }
    }
}
