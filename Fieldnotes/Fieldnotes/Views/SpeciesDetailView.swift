import FieldnotesCore
import SwiftUI

struct SpeciesDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var summary: SpeciesSummary

    @State private var shareItem: ShareImageItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                navRow

                if summary.bestSource == .audio {
                    SignatureCallModule(clipURL: bestClipURL, isBlocked: model.isListening)
                } else {
                    SpecimenPlateModule(taxon: summary.taxon, similarity: bestScoreDisplay.value)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Masthead(title: summary.commonName, subtitle: summary.scientificName, titleSize: 36, titleWeight: .semibold)
                }

                HStack(spacing: 10) {
                    if summary.bestSource == .audio {
                        MetricChip(value: bestScoreDisplay.value, label: "best", valueColor: .rust)
                    } else {
                        SimilarityChip(value: bestScoreDisplay.value, unit: "similarity")
                    }
                    MetricChip(value: "\(summary.count)", label: "detections", valueColor: .ink)
                    if isNewLifer {
                        TagChip(text: "new", textColor: .ink, fill: .paperCard, borderColor: .ink)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(sectionTitle)
                        .padding(.bottom, 6)
                    ForEach(detections) { detection in
                        DetectionRow(detection: detection)
                    }
                }
            }
            .padding(.horizontal, AlmanacLayout.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, .tabBarClearance)
        }
        .almanacBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    private var navRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹")
                    .font(.serif(30, .regular))
                    .foregroundStyle(Color.rust)
            }
            .buttonStyle(.plain)

            Spacer()

            Eyebrow("Field Record", color: .inkSoft)

            Spacer()

            Button {
                shareFieldCard()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.rust)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func shareFieldCard() {
        let card = FieldCardView(
            commonName: summary.commonName,
            scientificName: summary.scientificName,
            taxon: summary.taxon,
            source: summary.bestSource,
            metricValue: bestScoreDisplay.value,
            metricLabel: bestScoreDisplay.label,
            dateText: summary.lastSeen.formatted(.dateTime.month(.abbreviated).day().year()),
            placeText: placeText
        )
        if let image = renderFieldCard(card) {
            shareItem = ShareImageItem(image: image)
        }
    }

    private var placeText: String? {
        guard let located = detections.first(where: { $0.latitude != nil && $0.longitude != nil }),
              let latitude = located.latitude,
              let longitude = located.longitude else {
            return nil
        }
        return String(format: "%.2f, %.2f", latitude, longitude)
    }

    private var detections: [FieldDetection] {
        model.detections(for: summary)
    }

    private var bestClipURL: URL? {
        detections.first { $0.clipURL != nil }?.clipURL
    }

    private var bestScoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: summary.bestSource, score: summary.bestConfidence)
    }

    /// A recent addition to the life list — first recorded within the last week.
    private var isNewLifer: Bool {
        summary.firstSeen >= Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private var sectionTitle: String {
        summary.bestSource == .audio ? "Your Recordings" : "BioCAP · Top Matches"
    }
}

// MARK: - Audio: signature call module (§6.2)

private struct SignatureCallModule: View {
    var clipURL: URL?
    var isBlocked: Bool

    private let bars = Sonogram.sample(count: 38)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Signature Call")

            HStack(spacing: 16) {
                ClipPlaybackButton(url: clipURL, isBlocked: isBlocked, style: .hero)

                Sonogram(heights: bars)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 64, alignment: .center)
                    .clipped()
            }

            Text("0:00 / 0:14")
                .font(.mono(11, .regular))
                .tracking(.tracking(0.08, at: 11))
                .foregroundStyle(Color.monoLabel)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.paperCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ink, lineWidth: 1.5))
    }
}

// MARK: - Photo: specimen plate module (§6.2)

private struct SpecimenPlateModule: View {
    var taxon: Taxon
    var similarity: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotoFrame(categoryTag: taxon.almanacTag) {
                ZStack {
                    Color.paperCardAlt
                    Image(systemName: taxon.glyph)
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Color.ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
            }

            HStack {
                SimilarityChip(value: similarity, unit: "similarity")
                Spacer()
            }
        }
    }
}

extension Taxon {
    var glyph: String {
        switch self {
        case .bird: return "bird"
        case .mammal: return "hare"
        case .amphibian: return "drop"
        case .reptile: return "lizard"
        case .insect: return "ant"
        case .unknown: return "questionmark"
        }
    }

    var almanacTag: String {
        switch self {
        case .bird: return "Aves"
        case .mammal: return "Mammalia"
        case .amphibian: return "Amphibia"
        case .reptile: return "Reptilia"
        case .insect: return "Insecta"
        case .unknown: return "Unknown"
        }
    }
}
