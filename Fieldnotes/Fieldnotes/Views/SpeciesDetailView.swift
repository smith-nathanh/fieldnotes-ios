import FieldnotesCore
import SwiftUI

struct SpeciesDetailView: View {
    @EnvironmentObject private var model: AppModel
    var summary: SpeciesSummary

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TaxonBadge(taxon: summary.taxon)
                        Text(summary.taxon.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(summary.scientificName)
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        StatValue(title: "Clips", value: "\(summary.count)")
                        StatValue(title: "Best", value: "\(Int(summary.bestConfidence * 100))%")
                        StatValue(title: "First", value: summary.firstSeen.formatted(.dateTime.month().day()))
                        StatValue(title: "Last", value: summary.lastSeen.formatted(.dateTime.month().day()))
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Recordings") {
                ForEach(model.detections(for: summary)) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
        .navigationTitle(summary.commonName)
    }
}

private struct StatValue: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
