import FieldnotesCore
import SwiftUI

struct TaxonBadge: View {
    var taxon: Taxon

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(background, in: Circle())
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
            return .blue
        case .mammal:
            return .brown
        case .amphibian:
            return .green
        case .insect:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private var background: Color {
        foreground.opacity(0.14)
    }
}
