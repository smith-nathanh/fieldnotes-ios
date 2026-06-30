import FieldnotesCore
import SwiftUI

struct TaxonBadge: View {
    var taxon: Taxon

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(FieldStyle.paperRecessed, in: Circle())
            .overlay {
                Circle()
                    .stroke(foreground.opacity(0.28), lineWidth: 1)
            }
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
        case .insect:
            return "ant"
        case .unknown:
            return "questionmark"
        }
    }

    private var foreground: Color {
        switch taxon {
        case .bird:
            return FieldStyle.sky
        case .mammal:
            return FieldStyle.clay
        case .amphibian:
            return FieldStyle.leaf
        case .insect:
            return FieldStyle.moss
        case .unknown:
            return FieldStyle.inkFaint
        }
    }
}
