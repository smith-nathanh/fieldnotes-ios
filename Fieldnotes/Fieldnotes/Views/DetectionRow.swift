import FieldnotesCore
import SwiftUI

struct DetectionRow: View {
    var detection: FieldDetection

    var body: some View {
        HStack(spacing: 12) {
            TaxonBadge(taxon: detection.taxon)
            VStack(alignment: .leading, spacing: 3) {
                Text(detection.commonName)
                    .font(.subheadline.weight(.semibold))
                Text(detection.detectedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ClipPlaybackButton(url: detection.clipURL)
            Text("\(Int(detection.confidence * 100))%")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(confidenceColor)
        }
        .padding(.vertical, 6)
    }

    private var confidenceColor: Color {
        if detection.confidence >= 0.85 {
            return .green
        }
        if detection.confidence >= 0.75 {
            return .orange
        }
        return .secondary
    }
}
