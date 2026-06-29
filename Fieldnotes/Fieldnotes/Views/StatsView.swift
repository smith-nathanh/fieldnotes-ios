import FieldnotesCore
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.detections.isEmpty {
                    ContentUnavailableView("No stats yet", systemImage: "chart.bar.xaxis")
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatTile(title: "Today", value: "\(todayDetections.count)", detail: "\(todaySpeciesCount) species")
                            StatTile(title: "Week", value: "\(weekDetections.count)", detail: "\(weekSpeciesCount) species")
                            StatTile(title: "Species", value: "\(model.summaries.count)", detail: "\(model.detections.count) detections")
                            StatTile(title: "Best", value: bestConfidence, detail: bestSpeciesName)
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Top Species") {
                        ForEach(topSpecies) { summary in
                            NavigationLink {
                                SpeciesDetailView(summary: summary)
                            } label: {
                                StatsSpeciesRow(summary: summary)
                            }
                        }
                    }

                    Section("First Detections") {
                        ForEach(firstDetections) { summary in
                            NavigationLink {
                                SpeciesDetailView(summary: summary)
                            } label: {
                                FirstDetectionRow(summary: summary)
                            }
                        }
                    }

                    Section("Recent Activity") {
                        ForEach(recentActivity) { bucket in
                            HStack {
                                Text(bucket.title)
                                Spacer()
                                Text("\(bucket.count)")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }

    private var todayDetections: [FieldDetection] {
        model.detections.filter { Calendar.current.isDateInToday($0.detectedAt) }
    }

    private var weekDetections: [FieldDetection] {
        let start = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return model.detections.filter { $0.detectedAt >= start }
    }

    private var todaySpeciesCount: Int {
        Set(todayDetections.map(\.scientificName)).count
    }

    private var weekSpeciesCount: Int {
        Set(weekDetections.map(\.scientificName)).count
    }

    private var bestDetection: FieldDetection? {
        model.detections.max { $0.confidence < $1.confidence }
    }

    private var bestConfidence: String {
        guard let bestDetection else {
            return "-"
        }
        return "\(Int(bestDetection.confidence * 100))%"
    }

    private var bestSpeciesName: String {
        bestDetection?.commonName ?? "No detections"
    }

    private var topSpecies: [SpeciesSummary] {
        Array(model.summaries.sorted {
            if $0.count == $1.count {
                return $0.bestConfidence > $1.bestConfidence
            }
            return $0.count > $1.count
        }.prefix(8))
    }

    private var firstDetections: [SpeciesSummary] {
        Array(model.summaries.sorted {
            if $0.firstSeen == $1.firstSeen {
                return $0.commonName < $1.commonName
            }
            return $0.firstSeen > $1.firstSeen
        }.prefix(8))
    }

    private var recentActivity: [ActivityBucket] {
        [
            ActivityBucket(title: "Last hour", count: countDetections(since: Date().addingTimeInterval(-60 * 60))),
            ActivityBucket(title: "Last 24 hours", count: countDetections(since: Date().addingTimeInterval(-24 * 60 * 60))),
            ActivityBucket(title: "Last 7 days", count: weekDetections.count),
        ]
    }

    private func countDetections(since date: Date) -> Int {
        model.detections.filter { $0.detectedAt >= date }.count
    }
}

private struct StatTile: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct StatsSpeciesRow: View {
    var summary: SpeciesSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.commonName)
                    .font(.subheadline.weight(.semibold))
                Text(summary.scientificName)
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(summary.count)")
                    .font(.body.monospacedDigit().weight(.medium))
                Text("\(Int(summary.bestConfidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FirstDetectionRow: View {
    var summary: SpeciesSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.commonName)
                    .font(.subheadline.weight(.semibold))
                Text(summary.firstSeen, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(summary.count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityBucket: Identifiable {
    var id: String { title }
    var title: String
    var count: Int
}
