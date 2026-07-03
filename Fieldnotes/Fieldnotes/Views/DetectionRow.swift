import FieldnotesCore
import SwiftUI

struct DetectionRow: View {
    @EnvironmentObject private var model: AppModel

    var detection: FieldDetection

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TaxonBadge(taxon: detection.taxon)
            VStack(alignment: .leading, spacing: 3) {
                Text(detection.commonName)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(FieldStyle.ink)
                Text(detection.detectedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(FieldStyle.inkFaint)
            }
            Spacer()
            ClipPlaybackButton(url: detection.clipURL, isBlocked: model.isListening)
            VStack(alignment: .trailing, spacing: 2) {
                Text(scoreDisplay.value)
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(scoreDisplay.color)
                Text(scoreDisplay.label)
                    .font(.caption2.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(FieldStyle.inkFaint)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FieldStyle.rule)
                .frame(height: 0.5)
        }
    }

    private var scoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: detection.source, score: detection.confidence)
    }
}
