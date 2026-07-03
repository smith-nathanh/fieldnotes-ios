import FieldnotesCore
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Masthead(title: "Statistics", eyebrow: "Field Summary")

                    if model.detections.isEmpty {
                        AlmanacEmpty("No stats yet", message: "log a few detections to see the ledger")
                    } else {
                        OverviewPanel(metrics: overviewMetrics)

                        RankedPanel(
                            title: "Top Species",
                            subtitle: "most heard, all time",
                            summaries: topSpecies
                        )

                        ConfidenceDistributionPanel(bins: confidenceBins)

                        TaxonMixPanel(rows: taxonRows)

                        RegionPanel(regions: fieldRegions, locatedCount: locatedDetections.count)
                    }
                }
                .padding(.horizontal, AlmanacLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, .tabBarClearance)
            }
            .almanacBackground()
            .toolbar(.hidden, for: .navigationBar)
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
            confidenceBin(title: "90-100%", range: 0.90...1.00),
            confidenceBin(title: "75-89%", range: 0.75..<0.90),
            confidenceBin(title: "60-74%", range: 0.60..<0.75),
            confidenceBin(title: "< 60%", range: 0.00..<0.60),
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

    private func confidenceBin(title: String, range: ClosedRange<Float>) -> DistributionBin {
        DistributionBin(
            title: title,
            count: audioDetections.filter { range.contains($0.confidence) }.count,
            total: audioDetections.count
        )
    }

    private func confidenceBin(title: String, range: Range<Float>) -> DistributionBin {
        DistributionBin(
            title: title,
            count: audioDetections.filter { range.contains($0.confidence) }.count,
            total: audioDetections.count
        )
    }
}

// MARK: - Section scaffold

private struct StatSection<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.mono(10, .regular))
                        .tracking(.tracking(0.04, at: 10))
                        .foregroundStyle(Color.monoLabel)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BarTrack: View {
    var fraction: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline)
                Capsule()
                    .fill(Color.rust)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Panels

private struct OverviewPanel: View {
    var metrics: [StatMetric]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(metrics) { metric in
                MetricBlock(title: metric.title, value: metric.value)
            }
        }
    }
}

private struct RankedPanel: View {
    var title: String
    var subtitle: String
    var summaries: [SpeciesSummary]

    var body: some View {
        StatSection(title: title, subtitle: subtitle) {
            VStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    NavigationLink {
                        SpeciesDetailView(summary: summary)
                    } label: {
                        LedgerRow(
                            label: String(format: "%02d", index + 1),
                            detail: summary.commonName,
                            value: "\(summary.count)"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ConfidenceDistributionPanel: View {
    var bins: [DistributionBin]

    var body: some View {
        StatSection(title: "Confidence", subtitle: "how strongly saved audio scored") {
            VStack(spacing: 14) {
                ForEach(bins) { bin in
                    DistributionRow(bin: bin)
                }
            }
        }
    }
}

private struct TaxonMixPanel: View {
    var rows: [TaxonRow]

    var body: some View {
        StatSection(title: "Taxa", subtitle: "which kinds of visitors are logged") {
            VStack(spacing: 14) {
                ForEach(rows) { row in
                    VStack(spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.taxon.displayName)
                                .font(.serif(18))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("\(row.count)")
                                .font(.serif(19, .semibold))
                                .foregroundStyle(Color.rust)
                            Text("\(row.percent)%")
                                .font(.mono(10, .regular))
                                .tracking(.tracking(0.06, at: 10))
                                .foregroundStyle(Color.monoLabel)
                                .frame(width: 40, alignment: .trailing)
                        }
                        BarTrack(fraction: CGFloat(row.percent) / 100)
                    }
                }
            }
        }
    }
}

private struct RegionPanel: View {
    var regions: [FieldRegion]
    var locatedCount: Int

    var body: some View {
        StatSection(title: "Field Regions", subtitle: regionSubtitle) {
            if regions.isEmpty {
                Text("No location-tagged detections yet")
                    .font(.serif(17))
                    .foregroundStyle(Color.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(regions.prefix(6).enumerated()), id: \.element.id) { index, region in
                        RegionRow(index: index + 1, region: region)
                    }
                }
            }
        }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "Area %02d", index))
                    .font(.mono(11, .medium))
                    .tracking(.tracking(0.08, at: 11))
                    .foregroundStyle(Color.rust)
                Text(region.key.coordinateLabel)
                    .font(.mono(10, .regular))
                    .tracking(.tracking(0.04, at: 10))
                    .foregroundStyle(Color.monoLabel)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(region.count)")
                    .font(.serif(19, .semibold))
                    .foregroundStyle(Color.ink)
                Text("\(region.speciesCount) species")
                    .font(.mono(9, .regular))
                    .tracking(.tracking(0.06, at: 9))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.monoLabel)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
}

private struct DistributionRow: View {
    var bin: DistributionBin

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(bin.title)
                    .font(.mono(11, .medium))
                    .tracking(.tracking(0.06, at: 11))
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                Text("\(bin.count)")
                    .font(.serif(19, .semibold))
                    .foregroundStyle(Color.rust)
                Text("\(bin.percent)%")
                    .font(.mono(10, .regular))
                    .tracking(.tracking(0.06, at: 10))
                    .foregroundStyle(Color.monoLabel)
                    .frame(width: 40, alignment: .trailing)
            }
            BarTrack(fraction: bin.fraction)
        }
    }
}

// MARK: - Models

private struct StatMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
}

private struct DistributionBin: Identifiable {
    var id: String { title }
    var title: String
    var count: Int
    var total: Int

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
