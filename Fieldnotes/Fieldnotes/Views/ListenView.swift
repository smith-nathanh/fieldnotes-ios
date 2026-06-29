import FieldnotesCore
import SwiftUI

struct ListenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ListenHero(
                        isListening: model.isListening,
                        status: model.status,
                        action: model.toggleListening
                    )

                    DiagnosticsPanel(diagnostics: model.diagnostics)

                    FieldControls(
                        confidenceThreshold: model.confidenceThreshold,
                        privacyFilterEnabled: model.privacyFilterEnabled,
                        isLocked: model.isListening,
                        onThresholdChange: model.setConfidenceThreshold,
                        onPrivacyChange: model.setPrivacyFilterEnabled
                    )

                    RecentHitsList(detections: model.recentHits)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(FieldTheme.background.ignoresSafeArea())
            .navigationTitle("Listen")
            .toolbarBackground(FieldTheme.background, for: .navigationBar)
        }
    }
}

private enum FieldTheme {
    static let background = Color(red: 0.965, green: 0.953, blue: 0.918)
    static let panel = Color(red: 0.996, green: 0.992, blue: 0.973)
    static let recessed = Color(red: 0.902, green: 0.894, blue: 0.855)
    static let ink = Color(red: 0.105, green: 0.090, blue: 0.070)
    static let secondaryInk = Color(red: 0.330, green: 0.292, blue: 0.225)
    static let mutedInk = Color(red: 0.540, green: 0.500, blue: 0.430)
    static let moss = Color(red: 0.255, green: 0.330, blue: 0.220)
    static let leaf = Color(red: 0.185, green: 0.520, blue: 0.310)
    static let amber = Color(red: 0.710, green: 0.410, blue: 0.130)
    static let hairline = Color.black.opacity(0.09)
}

private struct FieldPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(FieldTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FieldTheme.hairline)
            }
            .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private extension View {
    func fieldPanel() -> some View {
        modifier(FieldPanelModifier())
    }
}

private struct ListenHero: View {
    var isListening: Bool
    var status: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(isListening ? FieldTheme.leaf.opacity(0.16) : FieldTheme.recessed)
                        .frame(width: 184, height: 184)
                    Circle()
                        .strokeBorder(FieldTheme.panel.opacity(0.75), lineWidth: 10)
                        .frame(width: 160, height: 160)
                    Circle()
                        .stroke(isListening ? FieldTheme.leaf : FieldTheme.moss, lineWidth: 2)
                        .frame(width: 142, height: 142)
                    Image(systemName: isListening ? "stop.fill" : "waveform")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(isListening ? FieldTheme.leaf : FieldTheme.moss)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Stop listening" : "Start listening")

            VStack(spacing: 5) {
                Text(status)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(FieldTheme.ink)
                Text(isListening ? "Live local classification" : "Tap to start a field session")
                    .font(.footnote.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(FieldTheme.mutedInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct SectionTitle: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(FieldTheme.secondaryInk)
    }
}

private struct StatusPill: View {
    var text: String
    var systemImage: String
    var color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct FieldMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(FieldTheme.ink)
            Text(title)
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(FieldTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldControls: View {
    var confidenceThreshold: Float
    var privacyFilterEnabled: Bool
    var isLocked: Bool
    var onThresholdChange: (Float) -> Void
    var onPrivacyChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Field Controls", systemImage: "slider.horizontal.3")
                Spacer()
                if isLocked {
                    StatusPill(text: "Locked", systemImage: "lock.fill", color: FieldTheme.amber)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FieldTheme.ink)
                    Spacer()
                    Text("\(Int(confidenceThreshold * 100))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FieldTheme.secondaryInk)
                }

                Slider(
                    value: Binding(
                        get: { Double(confidenceThreshold) },
                        set: { onThresholdChange(Float($0)) }
                    ),
                    in: 0.50...0.95,
                    step: 0.05
                )
                .tint(FieldTheme.moss)
                .disabled(isLocked)
            }

            Toggle(isOn: Binding(get: { privacyFilterEnabled }, set: onPrivacyChange)) {
                Label("Privacy filtering", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FieldTheme.ink)
            }
            .tint(FieldTheme.moss)
            .disabled(isLocked)
        }
        .fieldPanel()
    }
}

private struct DiagnosticsPanel: View {
    var diagnostics: DetectionDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                SectionTitle(title: "Diagnostics", systemImage: "gauge.with.dots.needle.bottom.50percent")
                Spacer()
                if diagnostics.privacySuppressed {
                    StatusPill(text: "Private", systemImage: "hand.raised.fill", color: FieldTheme.amber)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                FieldMetric(title: "Windows", value: "\(diagnostics.windowsProcessed)")
                FieldMetric(title: "Level", value: "\(Int(diagnostics.audioLevel * 100))%")
                FieldMetric(title: "Latency", value: latencyText)
                FieldMetric(title: "Range", value: rangeText)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Top Candidate")
                    .font(.caption2.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(FieldTheme.mutedInk)
                HStack(alignment: .firstTextBaseline) {
                    Text(topCandidateText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FieldTheme.ink)
                        .lineLimit(2)
                    Spacer()
                    Text(confidenceText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(confidenceColor)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .foregroundStyle(FieldTheme.moss)
                Text(audioInputText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FieldTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
        }
        .fieldPanel()
    }

    private var topCandidateText: String {
        diagnostics.topCandidateName ?? "-"
    }

    private var confidenceText: String {
        guard let confidence = diagnostics.topCandidateConfidence else {
            return "-"
        }
        return "\(Int(confidence * 100))%"
    }

    private var latencyText: String {
        guard let inferenceLatency = diagnostics.inferenceLatency else {
            return "-"
        }
        return "\(Int(inferenceLatency * 1_000)) ms"
    }

    private var rangeText: String {
        guard diagnostics.rangeFilterActive else {
            return "Off"
        }
        guard let rangeSpeciesCount = diagnostics.rangeSpeciesCount else {
            return "On"
        }
        return "\(rangeSpeciesCount)"
    }

    private var audioInputText: String {
        diagnostics.audioInputName ?? "Mic route unknown"
    }

    private var confidenceColor: Color {
        guard let confidence = diagnostics.topCandidateConfidence else {
            return FieldTheme.mutedInk
        }
        if confidence >= 0.85 {
            return FieldTheme.leaf
        }
        if confidence >= 0.70 {
            return FieldTheme.amber
        }
        return FieldTheme.mutedInk
    }
}

private struct RecentHitsList: View {
    var detections: [FieldDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recent Hits", systemImage: "clock")

            if detections.isEmpty {
                ContentUnavailableView("No detections yet", systemImage: "waveform.badge.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .foregroundStyle(FieldTheme.mutedInk)
            } else {
                ForEach(detections) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldPanel()
    }
}
