import FieldnotesCore
import SwiftUI

struct DetectionRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var placeNames: PlaceNameStore

    var detection: FieldDetection

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TaxonBadge(taxon: detection.taxon, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(detection.commonName)
                    .font(.serif(18, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(metadataText)
                    .font(.mono(10, .regular))
                    .tracking(.tracking(0.06, at: 10))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.monoLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            ClipPlaybackButton(url: detection.clipURL, isBlocked: model.isListening)

            VStack(alignment: .trailing, spacing: 2) {
                Text(scoreDisplay.value)
                    .font(.serif(18, .semibold))
                    .foregroundStyle(scoreDisplay.color)
                Text(scoreDisplay.label.uppercased())
                    .font(.mono(9, .regular))
                    .tracking(.tracking(0.08, at: 9))
                    .foregroundStyle(Color.monoLabel)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    private var scoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: detection.source, score: detection.evidenceScore)
    }

    private var placeName: String? {
        guard let latitude = detection.latitude, let longitude = detection.longitude else {
            return nil
        }
        return placeNames.name(latitude: latitude, longitude: longitude)
    }

    private var metadataText: String {
        let time = detection.detectedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if let placeName {
            return "\(time) · \(placeName)"
        }
        return time
    }
}
