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
                        FieldMetric(title: "Records", value: "\(summary.count)")
                        FieldMetric(title: bestScoreTitle, value: bestScoreDisplay.value)
                        FieldMetric(title: "First", value: summary.firstSeen.formatted(.dateTime.month().day()))
                        FieldMetric(title: "Last", value: summary.lastSeen.formatted(.dateTime.month().day()))
                    }
                }
                .fieldPanel()

                VStack(alignment: .leading, spacing: 12) {
                    FieldSectionLabel("records", systemImage: "list.bullet")
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

    private var bestScoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: summary.bestSource, score: summary.bestConfidence)
    }

    private var bestScoreTitle: String {
        switch summary.bestSource {
        case .audio:
            return "Best"
        case .photo:
            return "Similarity"
        }
    }
}
