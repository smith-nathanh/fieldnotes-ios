import FieldnotesCore
import SwiftUI

struct ListenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                Button {
                    model.toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.isListening ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.14))
                            .frame(width: 176, height: 176)
                        Circle()
                            .stroke(model.isListening ? Color.green : Color.accentColor, lineWidth: 3)
                            .frame(width: 148, height: 148)
                        Image(systemName: model.isListening ? "stop.fill" : "waveform")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(model.isListening ? Color.green : Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isListening ? "Stop listening" : "Start listening")

                VStack(spacing: 4) {
                    Text(model.status)
                        .font(.title2.weight(.semibold))
                    Text(model.isListening ? "Live local classification" : "Tap to start a field session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                RecentHitsList(detections: model.recentHits)
            }
            .padding()
            .navigationTitle("Listen")
        }
    }
}

private struct RecentHitsList: View {
    var detections: [FieldDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Hits")
                    .font(.headline)
                Spacer()
            }

            if detections.isEmpty {
                ContentUnavailableView("No detections yet", systemImage: "waveform.badge.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(detections) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
