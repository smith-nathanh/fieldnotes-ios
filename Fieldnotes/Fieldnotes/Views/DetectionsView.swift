import FieldnotesCore
import SwiftUI

struct DetectionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sortMode: LogSortMode = .recent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FieldPageHeader("Log")

                    Picker("Sort", selection: $sortMode) {
                        ForEach(LogSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(FieldStyle.moss)
                    .padding(4)
                    .background(FieldStyle.paperRecessed, in: Capsule())

                    if model.summaries.isEmpty {
                        ContentUnavailableView("No species logged", systemImage: "binoculars")
                            .foregroundStyle(FieldStyle.inkFaint)
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .fieldPanel()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedSummaries) { summary in
                                NavigationLink {
                                    SpeciesDetailView(summary: summary)
                                } label: {
                                    SpeciesSummaryCard(summary: summary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

    private var sortedSummaries: [SpeciesSummary] {
        switch sortMode {
        case .recent:
            return model.summaries.sorted {
                if $0.lastSeen == $1.lastSeen {
                    return $0.commonName < $1.commonName
                }
                return $0.lastSeen > $1.lastSeen
            }
        case .name:
            return model.summaries.sorted { $0.commonName < $1.commonName }
        case .count:
            return model.summaries.sorted {
                if $0.count == $1.count {
                    return $0.commonName < $1.commonName
                }
                return $0.count > $1.count
            }
        }
    }
}

private enum LogSortMode: String, CaseIterable, Identifiable {
    case recent
    case name
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .name:
            return "Name"
        case .count:
            return "Count"
        }
    }
}

private struct SpeciesSummaryCard: View {
    var summary: SpeciesSummary

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            TaxonBadge(taxon: summary.taxon)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.commonName)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(FieldStyle.ink)
                        .lineLimit(2)
                    Text(summary.scientificName)
                        .font(.subheadline.italic())
                        .foregroundStyle(FieldStyle.inkMuted)
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    if isNew {
                        FieldPill("new", color: FieldStyle.sky)
                    }
                    if isRecent {
                        FieldPill("recent", color: FieldStyle.leaf)
                    }
                    Text(summary.lastSeen, format: .relative(presentation: .named))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(FieldStyle.inkFaint)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(summary.count)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(FieldStyle.ink)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(scoreDisplay.value)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(scoreDisplay.color)
                    Text(scoreDisplay.label)
                        .font(.caption2.weight(.medium))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(FieldStyle.inkFaint)
                }
            }
        }
        .fieldPanel()
    }

    private var scoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: summary.bestSource, score: summary.bestConfidence)
    }

    private var isNew: Bool {
        Calendar.current.isDate(summary.firstSeen, inSameDayAs: Date())
    }

    private var isRecent: Bool {
        summary.lastSeen >= Date().addingTimeInterval(-24 * 60 * 60)
    }
}
