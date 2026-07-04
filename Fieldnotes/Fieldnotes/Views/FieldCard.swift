import FieldnotesCore
import SwiftUI
import UIKit

// MARK: - Field card (§9.7)

/// A printable/shareable card of a detection in the Almanac style, reusing the
/// Species Detail chrome at fixed card dimensions. Rendered to an image via
/// `ImageRenderer` and shared. Kept free of environment dependencies so it
/// renders correctly in isolation.
struct FieldCardView: View {
    var commonName: String
    var scientificName: String
    var taxon: Taxon
    var source: DetectionSource
    var metricValue: String
    var metricLabel: String
    var dateText: String
    var placeText: String?

    private let bars = Sonogram.sample(count: 46)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                DoubleRule()
                Eyebrow("Fieldnotes · Field Record")
                Text(commonName)
                    .font(.serif(32, .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(scientificName)
                    .font(.serifItalic(16))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if source == .audio {
                Sonogram(heights: bars)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 88, alignment: .center)
                    .clipped()
            } else {
                ZStack {
                    Color.paperCardAlt
                    Image(systemName: taxon.glyph)
                        .font(.system(size: 60, weight: .regular))
                        .foregroundStyle(Color.ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.ink, lineWidth: 1.5))
            }

            HStack {
                MetricChip(value: metricValue, label: metricLabel, valueColor: .rust)
                Spacer()
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.ink).frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text(dateText.uppercased())
                        .font(.mono(10, .medium))
                        .tracking(.tracking(0.08, at: 10))
                        .foregroundStyle(Color.monoLabel)
                    Spacer()
                    if let placeText {
                        Text(placeText.uppercased())
                            .font(.mono(10, .regular))
                            .tracking(.tracking(0.06, at: 10))
                            .foregroundStyle(Color.monoLabel)
                    }
                }
                Eyebrow("A Naturalist's Record", color: .inkSoft, size: 9)
            }
        }
        .padding(26)
        .frame(width: 360, height: 480)
        .background(Color.paper)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.ink, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@MainActor
func renderFieldCard(_ card: FieldCardView) -> UIImage? {
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    return renderer.uiImage
}

// MARK: - Share sheet

struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
