import FieldnotesCore
import SwiftUI

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
