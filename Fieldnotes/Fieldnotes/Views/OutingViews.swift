import FieldnotesCore
import SwiftUI

struct TripStatusBanner: View {
    var trip: Trip?
    var locationTaggingEnabled: Bool
    var onStart: () -> Void
    var onEnd: () -> Void
    @State private var confirmWithoutLocation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip == nil ? "map" : "map.fill")
                .foregroundStyle(Color.rust)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(trip == nil ? "No active trip" : "Trip active")
                Text(trip?.name ?? "Group your next observations")
                    .font(.serif(16, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            Spacer()
            Button(trip == nil ? "Start" : "End") {
                if trip == nil, !locationTaggingEnabled {
                    confirmWithoutLocation = true
                } else if trip == nil {
                    onStart()
                } else {
                    onEnd()
                }
            }
            .font(.mono(11, .semibold))
            .foregroundStyle(Color.rust)
        }
        .padding(14)
        .background(Color.paperCard)
        .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.lineWarm, lineWidth: 1) }
        .confirmationDialog(
            "Start without location tagging?",
            isPresented: $confirmWithoutLocation,
            titleVisibility: .visible
        ) {
            Button("Start Trip Without Map Locations", action: onStart)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Location tagging is off, so new observations may not appear on the Trip map.")
        }
    }
}

// MARK: - Shared formatting

private func timeOfDayTitle(_ date: Date) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: return "Morning"
    case 12..<17: return "Afternoon"
    case 17..<21: return "Evening"
    default: return "Night"
    }
}

private func durationLabel(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds < 60 {
        return "\(seconds)s"
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return "\(minutes) min"
    }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
}

private func outingMetrics(_ outing: Outing) -> String {
    "\(outing.speciesCount) species · \(outing.detectionCount) detections · \(durationLabel(outing.duration))"
}

// MARK: - Outing card (§9.3)

struct OutingCard: View {
    var outing: Outing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoubleRule()
                .padding(.bottom, 2)
            Eyebrow("Outing · \(outing.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
            Text(timeOfDayTitle(outing.startedAt))
                .font(.serif(28, .semibold))
                .foregroundStyle(Color.ink)
            Text(outingMetrics(outing).uppercased())
                .font(.mono(10, .regular))
                .tracking(.tracking(0.06, at: 10))
                .foregroundStyle(Color.monoLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

// MARK: - Outing detail (§9.3)

struct OutingDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var outing: Outing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                navRow

                Masthead(
                    title: timeOfDayTitle(outing.startedAt),
                    subtitle: dateSubtitle,
                    titleSize: 36,
                    titleWeight: .semibold
                )

                Text(outingMetrics(outing).uppercased())
                    .font(.mono(11, .regular))
                    .tracking(.tracking(0.06, at: 11))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Detections")
                        .padding(.bottom, 6)
                    ForEach(detections) { detection in
                        DetectionRow(detection: detection)
                    }
                }
            }
            .padding(.horizontal, AlmanacLayout.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, .tabBarClearance)
        }
        .almanacBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var navRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹")
                    .font(.serif(30, .regular))
                    .foregroundStyle(Color.rust)
            }
            .buttonStyle(.plain)

            Spacer()

            Eyebrow("Outing", color: .inkSoft)

            Spacer()

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.rust)
            }
        }
        .padding(.top, 4)
    }

    private var detections: [FieldDetection] {
        model.detections(for: outing)
    }

    private var dateSubtitle: String {
        let day = outing.startedAt.formatted(.dateTime.month(.abbreviated).day())
        let start = outing.startedAt.formatted(date: .omitted, time: .shortened)
        let end = outing.endedAt.formatted(date: .omitted, time: .shortened)
        return start == end ? "\(day) · \(start)" : "\(day) · \(start) – \(end)"
    }

    private var shareText: String {
        "Fieldnotes — \(timeOfDayTitle(outing.startedAt)) outing, \(outingMetrics(outing))"
    }
}

struct TripCard: View {
    var trip: Trip
    var detections: [FieldDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoubleRule().padding(.bottom, 2)
            Eyebrow(trip.isActive ? "Trip · Active" : "Trip")
            Text(trip.name)
                .font(.serif(28, .semibold))
                .foregroundStyle(Color.ink)
            Text("\(Set(detections.map(\.scientificName)).count) SPECIES · \(detections.count) OBSERVATIONS")
                .font(.mono(10, .regular))
                .foregroundStyle(Color.monoLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var trip: Trip
    @State private var mapFilter: TripMapFilter = .all
    @State private var editedName = ""
    @State private var editingName = false

    private var currentTrip: Trip { model.trips.first(where: { $0.id == trip.id }) ?? trip }
    private var detections: [FieldDetection] { model.detections(for: currentTrip) }
    private var displayedMapDetections: [FieldDetection] {
        detections.filter { detection in
            detection.latitude != nil && detection.longitude != nil &&
            (mapFilter.source == nil || detection.source == mapFilter.source)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button("‹") { dismiss() }
                        .font(.serif(30)).foregroundStyle(Color.rust)
                    Spacer()
                    Button("Rename") {
                        editedName = currentTrip.name
                        editingName = true
                    }
                    .font(.mono(11, .semibold)).foregroundStyle(Color.rust)
                }

                Masthead(title: currentTrip.name, subtitle: dateSubtitle, titleSize: 36)

                HStack(spacing: 12) {
                    MetricBlock(title: "Species", value: "\(speciesCount)")
                    MetricBlock(title: "Photos", value: "\(photoCount)")
                    MetricBlock(title: "Audio", value: "\(audioCount)")
                }

                AlmanacSection("Map") {
                    AlmanacSegmentedControl(
                        options: TripMapFilter.allCases.map { ($0, $0.title) },
                        selection: $mapFilter
                    )
                    if displayedMapDetections.isEmpty {
                        AlmanacEmpty("No mapped observations", message: "located observations appear here")
                    } else {
                        DetectionMapView(detections: displayedMapDetections, isInteractive: false) { _ in }
                            .frame(height: 260)
                    }
                }

                AlmanacSection("Observations") {
                    if detections.isEmpty {
                        AlmanacEmpty("No observations", message: "captures made during this trip appear here")
                    } else {
                        ForEach(detections) { detection in
                            HStack(alignment: .top) {
                                DetectionRow(detection: detection)
                                Menu {
                                    Button("Remove from Trip", role: .destructive) {
                                        model.setTrip(nil, for: detection.id)
                                    }
                                    ForEach(model.trips.filter { $0.id != currentTrip.id }) { destination in
                                        Button("Move to \(destination.name)") {
                                            model.setTrip(destination, for: detection.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(Color.rust)
                                        .padding(.top, 12)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AlmanacLayout.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, .tabBarClearance)
        }
        .almanacBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Rename Trip", isPresented: $editingName) {
            TextField("Trip name", text: $editedName)
            Button("Save") { model.renameTrip(currentTrip, to: editedName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var speciesCount: Int { Set(detections.map(\.scientificName)).count }
    private var photoCount: Int { detections.filter { $0.source == .photo }.count }
    private var audioCount: Int { detections.filter { $0.source == .audio }.count }
    private var dateSubtitle: String {
        let end = currentTrip.endedAt ?? Date()
        return currentTrip.startedAt.formatted(.dateTime.month(.abbreviated).day())
            + " – " + end.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private enum TripMapFilter: String, CaseIterable, Identifiable {
    case all, photos, audio
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var source: DetectionSource? {
        switch self {
        case .all: nil
        case .photos: .photo
        case .audio: .audio
        }
    }
}
