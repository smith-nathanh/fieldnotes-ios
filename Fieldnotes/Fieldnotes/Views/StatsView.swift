import FieldnotesCore
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FieldPageHeader("Statistics")

                    if model.detections.isEmpty {
                        ContentUnavailableView("No stats yet", systemImage: "chart.bar.xaxis")
                            .foregroundStyle(FieldStyle.inkFaint)
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .fieldPanel()
                    } else {
                        OverviewPanel(metrics: overviewMetrics)

                        RankedPanel(
                            title: "top species",
                            subtitle: "most heard, all time",
                            summaries: topSpecies
                        )

                        ConfidenceDistributionPanel(bins: confidenceBins)

                        TaxonMixPanel(rows: taxonRows)

                        RegionPanel(regions: fieldRegions, locatedCount: locatedDetections.count)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .fieldPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FieldStyle.paper, for: .navigationBar)
        }
    }

    private var todayDetections: [FieldDetection] {
        model.detections.filter { Calendar.current.isDateInToday($0.detectedAt) }
    }

    private var weekDetections: [FieldDetection] {
        let start = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return model.detections.filter { $0.detectedAt >= start }
    }

    private var audioDetections: [FieldDetection] {
        model.detections.filter { $0.source == .audio }
    }

    private var todaySpeciesCount: Int {
        Set(todayDetections.map(\.scientificName)).count
    }

    private var weekSpeciesCount: Int {
        Set(weekDetections.map(\.scientificName)).count
    }

    private var clipCount: Int {
        model.detections.filter { $0.clipURL != nil }.count
    }

    private var locatedDetections: [FieldDetection] {
        model.detections.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var bestDetection: FieldDetection? {
        audioDetections.max { $0.confidence < $1.confidence }
    }

    private var overviewMetrics: [StatMetric] {
        [
            StatMetric(title: "detections", value: "\(model.detections.count)"),
            StatMetric(title: "species", value: "\(model.summaries.count)"),
            StatMetric(title: "best audio", value: bestConfidence),
            StatMetric(title: "clips", value: "\(clipCount)"),
            StatMetric(title: "today", value: "\(todayDetections.count)"),
            StatMetric(title: "week", value: "\(weekDetections.count)"),
        ]
    }

    private var bestConfidence: String {
        guard let bestDetection else {
            return "-"
        }
        return "\(Int(bestDetection.confidence * 100))%"
    }

    private var topSpecies: [SpeciesSummary] {
        Array(model.summaries.sorted {
            if $0.count == $1.count {
                return $0.bestConfidence > $1.bestConfidence
            }
            return $0.count > $1.count
        }.prefix(8))
    }

    private var confidenceBins: [DistributionBin] {
        [
            confidenceBin(title: "90-100%", range: 0.90...1.00, color: FieldStyle.leaf),
            confidenceBin(title: "75-89%", range: 0.75..<0.90, color: FieldStyle.moss),
            confidenceBin(title: "60-74%", range: 0.60..<0.75, color: FieldStyle.clay),
            confidenceBin(title: "< 60%", range: 0.00..<0.60, color: FieldStyle.inkFaint),
        ]
    }

    private var taxonRows: [TaxonRow] {
        Taxon.allCases.compactMap { taxon in
            let count = model.detections.filter { $0.taxon == taxon }.count
            guard count > 0 else {
                return nil
            }
            return TaxonRow(taxon: taxon, count: count, total: model.detections.count)
        }
    }

    private var fieldRegions: [FieldRegion] {
        let grouped = Dictionary(grouping: locatedDetections, by: FieldRegionKey.init(detection:))

        return grouped.map { key, detections in
            let speciesCount = Set(detections.map(\.scientificName)).count
            return FieldRegion(
                key: key,
                count: detections.count,
                speciesCount: speciesCount,
                latestSeen: detections.map(\.detectedAt).max() ?? .distantPast
            )
        }
        .sorted {
            if $0.count == $1.count {
                return $0.latestSeen > $1.latestSeen
            }
            return $0.count > $1.count
        }
    }

    private func confidenceBin(title: String, range: ClosedRange<Float>, color: Color) -> DistributionBin {
        DistributionBin(
            title: title,
            count: audioDetections.filter { range.contains($0.confidence) }.count,
            total: audioDetections.count,
            color: color
        )
    }

    private func confidenceBin(title: String, range: Range<Float>, color: Color) -> DistributionBin {
        DistributionBin(
            title: title,
            count: audioDetections.filter { range.contains($0.confidence) }.count,
            total: audioDetections.count,
            color: color
        )
    }
}

private struct OverviewPanel: View {
    var metrics: [StatMetric]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                FieldMetric(title: metric.title, value: metric.value)
            }
        }
        .fieldPanel()
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }
}

private struct RankedPanel: View {
    var title: String
    var subtitle: String
    var summaries: [SpeciesSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                FieldSectionLabel(title)
                Text(subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(FieldStyle.inkFaint)
            }

            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                NavigationLink {
                    SpeciesDetailView(summary: summary)
                } label: {
                    FieldRuleRow(
                        label: String(format: "%02d", index + 1),
                        detail: summary.commonName,
                        value: "\(summary.count)"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .fieldPanel()
    }
}

private struct ConfidenceDistributionPanel: View {
    var bins: [DistributionBin]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                FieldSectionLabel("confidence")
                Text("how strongly BirdNET scored saved audio detections")
                    .font(.caption.monospaced())
                    .foregroundStyle(FieldStyle.inkFaint)
            }

            ForEach(bins) { bin in
                DistributionRow(bin: bin)
            }
        }
        .fieldPanel()
    }
}

private struct TaxonMixPanel: View {
    var rows: [TaxonRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                FieldSectionLabel("taxa")
                Text("which kinds of visitors are being logged")
                    .font(.caption.monospaced())
                    .foregroundStyle(FieldStyle.inkFaint)
            }

            ForEach(rows) { row in
                FieldRuleRow(
                    label: row.taxon.displayName,
                    detail: "\(row.percent)%",
                    value: "\(row.count)"
                )
            }
        }
        .fieldPanel()
    }
}

private struct RegionPanel: View {
    var regions: [FieldRegion]
    var locatedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                FieldSectionLabel("field regions")
                Text(regionSubtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(FieldStyle.inkFaint)
            }

            if regions.isEmpty {
                Text("No location-tagged detections yet")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(FieldStyle.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(regions.prefix(6).enumerated()), id: \.element.id) { index, region in
                    RegionRow(index: index + 1, region: region)
                }
            }
        }
        .fieldPanel()
    }

    private var regionSubtitle: String {
        if locatedCount == 0 {
            return "approximate areas appear after location is available"
        }
        return "\(locatedCount) location-tagged detections"
    }
}

private struct RegionRow: View {
    var index: Int
    var region: FieldRegion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Area %02d", index))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(FieldStyle.inkMuted)
                Text(region.key.coordinateLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(FieldStyle.inkFaint)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(region.count)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(FieldStyle.inkMuted)
                Text("\(region.speciesCount) species")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FieldStyle.inkFaint)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FieldStyle.rule)
                .frame(height: 0.5)
        }
    }
}

private struct DistributionRow: View {
    var bin: DistributionBin

    var body: some View {
        VStack(spacing: 6) {
            FieldRuleRow(label: bin.title, detail: "\(bin.percent)%", value: "\(bin.count)")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FieldStyle.paperRecessed)
                    Capsule()
                        .fill(bin.color.opacity(0.80))
                        .frame(width: proxy.size.width * bin.fraction)
                }
            }
            .frame(height: 7)
        }
    }
}

private struct FieldRuleRow: View {
    var label: String
    var detail: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(FieldStyle.inkMuted)
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(.body, design: .serif))
                .foregroundStyle(FieldStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(FieldStyle.inkMuted)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FieldStyle.rule)
                .frame(height: 0.5)
        }
    }
}

private struct StatMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
}

private struct DistributionBin: Identifiable {
    var id: String { label }
    var title: String
    var count: Int
    var total: Int
    var color: Color

    var label: String { title }

    var fraction: CGFloat {
        guard total > 0 else {
            return 0
        }
        return CGFloat(count) / CGFloat(total)
    }

    var percent: Int {
        guard total > 0 else {
            return 0
        }
        return Int((Double(count) / Double(total) * 100).rounded())
    }
}

private struct TaxonRow: Identifiable {
    var id: Taxon { taxon }
    var taxon: Taxon
    var count: Int
    var total: Int

    var percent: Int {
        guard total > 0 else {
            return 0
        }
        return Int((Double(count) / Double(total) * 100).rounded())
    }
}

private struct FieldRegion: Identifiable {
    var id: FieldRegionKey { key }
    var key: FieldRegionKey
    var count: Int
    var speciesCount: Int
    var latestSeen: Date
}

private struct FieldRegionKey: Hashable, Sendable {
    var latitudeBucket: Int
    var longitudeBucket: Int

    nonisolated init(detection: FieldDetection) {
        latitudeBucket = Self.bucket(detection.latitude ?? 0)
        longitudeBucket = Self.bucket(detection.longitude ?? 0)
    }

    nonisolated var coordinateLabel: String {
        let latitude = Double(latitudeBucket) / 20
        let longitude = Double(longitudeBucket) / 20
        return String(format: "%.2f, %.2f", latitude, longitude)
    }

    private nonisolated static func bucket(_ value: Double) -> Int {
        Int((value * 20).rounded())
    }
}

private extension Taxon {
    var displayName: String {
        switch self {
        case .bird:
            return "Birds"
        case .mammal:
            return "Mammals"
        case .amphibian:
            return "Amphibians"
        case .reptile:
            return "Reptiles"
        case .insect:
            return "Insects"
        case .unknown:
            return "Unknown"
        }
    }
}
