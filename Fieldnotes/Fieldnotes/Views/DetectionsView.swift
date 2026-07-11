import FieldnotesCore
import SwiftUI

struct DetectionsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var placeNames: PlaceNameStore
    @State private var logMode: LogMode = .species
    @State private var sortMode: LogSortMode = .recent
    @State private var placeFilterKey: String?
    @State private var outingFilter: Outing?
    @State private var mapSelection: SpeciesSummary?
    @State private var showMapSelection = false

    var body: some View {
        NavigationStack {
            Group {
                if logMode == .map {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, AlmanacLayout.screenPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 18)
                        mapContent
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header
                            if logMode == .species {
                                speciesContent
                            } else if logMode == .trips {
                                tripsContent
                            } else {
                                outingsContent
                            }
                        }
                        .padding(.horizontal, AlmanacLayout.screenPadding)
                        .padding(.top, 8)
                        .padding(.bottom, .tabBarClearance)
                    }
                }
            }
            .almanacBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showMapSelection) {
                if let mapSelection {
                    SpeciesDetailView(summary: mapSelection)
                }
            }
        }
    }

    private var header: some View {
        AlmanacSegmentedControl(
            options: LogMode.allCases.map { ($0, $0.title) },
            selection: $logMode
        )
    }

    @ViewBuilder
    private var mapContent: some View {
        if locatedDetections.isEmpty {
            VStack(spacing: 0) {
                AlmanacEmpty("No mapped detections", message: "detections with a location appear here")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AlmanacLayout.screenPadding)
        } else {
            DetectionMapView(detections: locatedDetections) { scientificName in
                if let summary = model.summaries.first(where: { $0.scientificName == scientificName }) {
                    mapSelection = summary
                    showMapSelection = true
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var locatedDetections: [FieldDetection] {
        model.detections.filter { $0.latitude != nil && $0.longitude != nil }
    }

    @ViewBuilder
    private var speciesContent: some View {
        AlmanacSegmentedControl(
            options: LogSortMode.allCases.map { ($0, $0.title) },
            selection: $sortMode
        )

        if !placeOptions.isEmpty || !model.outings.isEmpty {
            filterChips
        }

        let summaries = displayedSummaries
        if model.summaries.isEmpty {
            AlmanacEmpty("No species logged", message: "detections you save appear here")
        } else if summaries.isEmpty {
            AlmanacEmpty("No species here", message: "nothing matches this filter")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
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

    private var filterChips: some View {
        HStack(spacing: 8) {
            if !placeOptions.isEmpty {
                Menu {
                    Button("All places") { placeFilterKey = nil }
                    ForEach(placeOptions) { option in
                        Button(option.name) { placeFilterKey = option.key }
                    }
                } label: {
                    FilterChipLabel(icon: "mappin", text: placeFilterText, active: placeFilterKey != nil)
                }
            }
            if !model.outings.isEmpty {
                Menu {
                    Button("All outings") { outingFilter = nil }
                    ForEach(model.outings) { outing in
                        Button(Self.outingLabel(outing)) { outingFilter = outing }
                    }
                } label: {
                    FilterChipLabel(
                        icon: "clock",
                        text: outingFilter.map(Self.outingLabel) ?? "All outings",
                        active: outingFilter != nil
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var displayedSummaries: [SpeciesSummary] {
        let base: [SpeciesSummary]
        if placeFilterKey == nil && outingFilter == nil {
            base = model.summaries
        } else {
            let filtered = model.detections.filter { detection in
                (outingFilter == nil || detection.outingId == outingFilter?.id) &&
                (placeFilterKey == nil || Self.placeKey(detection) == placeFilterKey)
            }
            base = DetectionStore(detections: filtered).summaries()
        }
        return sorted(base)
    }

    private var placeOptions: [PlaceOption] {
        let located = model.detections.filter { $0.latitude != nil && $0.longitude != nil }
        let grouped = Dictionary(grouping: located) { Self.placeKey($0) ?? "" }
        return grouped.compactMap { key, detections -> PlaceOption? in
            guard let detection = detections.first,
                  let latitude = detection.latitude,
                  let longitude = detection.longitude else {
                return nil
            }
            return PlaceOption(key: key, name: placeNames.name(latitude: latitude, longitude: longitude) ?? key)
        }
        .sorted { $0.name < $1.name }
    }

    private var placeFilterText: String {
        guard let placeFilterKey else {
            return "All places"
        }
        return placeOptions.first { $0.key == placeFilterKey }?.name ?? "All places"
    }

    static func placeKey(_ detection: FieldDetection) -> String? {
        guard let latitude = detection.latitude, let longitude = detection.longitude else {
            return nil
        }
        return String(format: "%.3f,%.3f", latitude, longitude)
    }

    static func outingLabel(_ outing: Outing) -> String {
        outing.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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

    @ViewBuilder
    private var tripsContent: some View {
        if model.trips.isEmpty {
            VStack(spacing: 18) {
                AlmanacEmpty("No trips yet", message: "start a trip to group photos and audio across multiple days")
                Button("Start Trip", action: model.startTrip)
                    .buttonStyle(AlmanacSecondaryButton())
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.trips) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        TripCard(trip: trip, detections: model.detections(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sorted(_ summaries: [SpeciesSummary]) -> [SpeciesSummary] {
        switch sortMode {
        case .recent:
            return summaries.sorted {
                if $0.lastSeen == $1.lastSeen {
                    return $0.commonName < $1.commonName
                }
                return $0.lastSeen > $1.lastSeen
            }
        case .name:
            return summaries.sorted { $0.commonName < $1.commonName }
        case .count:
            return summaries.sorted {
                if $0.count == $1.count {
                    return $0.commonName < $1.commonName
                }
                return $0.count > $1.count
            }
        }
    }
}

private struct PlaceOption: Identifiable, Equatable {
    var key: String
    var name: String
    var id: String { key }
}

private struct FilterChipLabel: View {
    var icon: String
    var text: String
    var active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text.uppercased())
                .font(.mono(10, .medium))
                .tracking(.tracking(0.08, at: 10))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(active ? Color.paper : Color.segInactive)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if active {
                Capsule().fill(Color.ink)
            } else {
                Capsule().stroke(Color.lineWarm, lineWidth: 1)
            }
        }
    }
}

private enum LogMode: String, CaseIterable, Identifiable {
    case species
    case trips
    case outings
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .species:
            return "Species"
        case .trips:
            return "Trips"
        case .outings:
            return "Outings"
        case .map:
            return "Map"
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
