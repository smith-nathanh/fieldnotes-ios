import FieldnotesCore
import SwiftUI

struct DetectionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var logMode: LogMode = .species
    @State private var sortMode: LogSortMode = .recent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(title: "Log", eyebrow: "A Naturalist's Record")

                    AlmanacSegmentedControl(
                        options: LogMode.allCases.map { ($0, $0.title) },
                        selection: $logMode
                    )

                    switch logMode {
                    case .species:
                        speciesContent
                    case .outings:
                        outingsContent
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

    @ViewBuilder
    private var speciesContent: some View {
        AlmanacSegmentedControl(
            options: LogSortMode.allCases.map { ($0, $0.title) },
            selection: $sortMode
        )

        if model.summaries.isEmpty {
            AlmanacEmpty("No species logged", message: "detections you save appear here")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedSummaries.enumerated()), id: \.element.id) { index, summary in
                    NavigationLink {
                        SpeciesDetailView(summary: summary)
                    } label: {
                        SpeciesLogRow(index: index + 1, summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var outingsContent: some View {
        if model.outings.isEmpty {
            AlmanacEmpty("No outings yet", message: "start a listening session to log one")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.outings) { outing in
                    NavigationLink {
                        OutingDetailView(outing: outing)
                    } label: {
                        OutingCard(outing: outing)
                    }
                    .buttonStyle(.plain)
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
        }
    }
}

private enum LogMode: String, CaseIterable, Identifiable {
    case species
    case outings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .species:
            return "Species"
        case .outings:
            return "Outings"
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

private struct SpeciesLogRow: View {
    var index: Int
    var summary: SpeciesSummary

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            PlateBadge(index: String(format: "%02d", index))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.commonName)
                    .font(.serif(19, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(summary.scientificName)
                    .font(.serifItalic(13))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if isNew {
                        TagChip(text: "new", textColor: .ink, fill: .paperCard, borderColor: .ink)
                    }
                    if isRecent {
                        TagChip(text: "recent", textColor: .rust, fill: Color.rust.opacity(0.12), borderColor: nil)
                    }
                    Text(summary.lastSeen, format: .relative(presentation: .named))
                        .font(.mono(10, .regular))
                        .tracking(.tracking(0.04, at: 10))
                        .foregroundStyle(Color.monoLabel)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(summary.count)")
                    .font(.serif(22, .semibold))
                    .foregroundStyle(Color.rust)
                Text(scoreDisplay.value + " " + scoreDisplay.label)
                    .font(.mono(9, .regular))
                    .tracking(.tracking(0.06, at: 9))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.monoLabel)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    private var scoreDisplay: DetectionScoreDisplay {
        DetectionScoreDisplay(source: summary.bestSource, score: summary.bestConfidence)
    }

    private var isNew: Bool {
        summary.firstSeen >= Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private var isRecent: Bool {
        summary.lastSeen >= Date().addingTimeInterval(-24 * 60 * 60)
    }
}
