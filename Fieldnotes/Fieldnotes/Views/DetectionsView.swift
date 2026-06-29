import FieldnotesCore
import SwiftUI

struct DetectionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.summaries.isEmpty {
                    ContentUnavailableView("No species logged", systemImage: "binoculars")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.summaries) { summary in
                        NavigationLink {
                            SpeciesDetailView(summary: summary)
                        } label: {
                            SpeciesSummaryRow(summary: summary)
                        }
                    }
                }
            }
            .navigationTitle("Detections")
        }
    }
}

private struct SpeciesSummaryRow: View {
    var summary: SpeciesSummary

    var body: some View {
        HStack(spacing: 12) {
            TaxonBadge(taxon: summary.taxon)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.commonName)
                    .font(.headline)
                Text(summary.scientificName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(summary.count)")
                    .font(.headline.monospacedDigit())
                Text("\(Int(summary.bestConfidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
