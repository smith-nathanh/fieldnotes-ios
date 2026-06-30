import FieldnotesCore
import SwiftUI

struct SpeciesDetailView: View {
    @EnvironmentObject private var model: AppModel
    var summary: SpeciesSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FieldPageHeader(
                    summary.commonName,
                    subtitle: summary.scientificName
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TaxonBadge(taxon: summary.taxon)
                        Text(summary.scientificName)
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(FieldStyle.inkMuted)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        FieldMetric(title: "Clips", value: "\(summary.count)")
                        FieldMetric(title: "Best", value: "\(Int(summary.bestConfidence * 100))%")
                        FieldMetric(title: "First", value: summary.firstSeen.formatted(.dateTime.month().day()))
                        FieldMetric(title: "Last", value: summary.lastSeen.formatted(.dateTime.month().day()))
                    }
                }
                .fieldPanel()

                VStack(alignment: .leading, spacing: 12) {
                    FieldSectionLabel("recordings", systemImage: "waveform")
                    ForEach(model.detections(for: summary)) { detection in
                        DetectionRow(detection: detection)
                    }
                }
                .fieldPanel()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .fieldPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FieldStyle.paper, for: .navigationBar)
    }
}
