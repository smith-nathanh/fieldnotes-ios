import FieldnotesCore
import SwiftUI

struct DetectionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sortMode: AtlasSortMode = .recent

    var body: some View {
        NavigationStack {
            List {
                if model.summaries.isEmpty {
                    ContentUnavailableView("No species logged", systemImage: "binoculars")
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(sortedSummaries) { summary in
                            NavigationLink {
                                SpeciesDetailView(summary: summary)
                            } label: {
                                SpeciesSummaryRow(summary: summary)
                            }
                        }
                    } header: {
                        Text("\(model.summaries.count) Species")
                    }
                }
            }
            .navigationTitle("Atlas")
            .toolbar {
                if !model.summaries.isEmpty {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(AtlasSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
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
        case .firstSeen:
            return model.summaries.sorted {
                if $0.firstSeen == $1.firstSeen {
                    return $0.commonName < $1.commonName
                }
                return $0.firstSeen > $1.firstSeen
            }
        }
    }
}

private enum AtlasSortMode: String, CaseIterable, Identifiable {
    case recent
    case name
    case count
    case firstSeen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .name:
            return "Name"
        case .count:
            return "Count"
        case .firstSeen:
            return "First Seen"
        }
    }
}

private struct SpeciesSummaryRow: View {
    var summary: SpeciesSummary

    var body: some View {
        HStack(spacing: 12) {
            TaxonBadge(taxon: summary.taxon)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.commonName)
                    .font(.headline)
                Text(summary.scientificName)
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if isNew {
                        SpeciesBadge(title: "New", color: .blue)
                    }
                    if isRecent {
                        SpeciesBadge(title: "Recent", color: .green)
                    }
                    Text(summary.lastSeen, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(summary.count)")
                    .font(.headline.monospacedDigit())
                Text("\(Int(summary.bestConfidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var isNew: Bool {
        Calendar.current.isDate(summary.firstSeen, inSameDayAs: Date())
    }

    private var isRecent: Bool {
        summary.lastSeen >= Date().addingTimeInterval(-24 * 60 * 60)
    }
}

private struct SpeciesBadge: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
