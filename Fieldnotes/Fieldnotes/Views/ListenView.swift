import FieldnotesCore
import SwiftUI

struct ListenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FieldPageHeader(
                        "Listen",
                        subtitle: model.isListening ? "Local classification is live" : nil
                    )

                    ListenControl(
                        isListening: model.isListening,
                        status: model.status,
                        action: model.toggleListening
                    )

                    LiveCandidatePanel(
                        diagnostics: model.diagnostics,
                        threshold: model.confidenceThreshold,
                        isListening: model.isListening
                    )

                    DiagnosticsPanel(diagnostics: model.diagnostics)

                    RecentHitsList(detections: model.recentHits)

                    FieldControls(
                        confidenceThreshold: model.confidenceThreshold,
                        privacyFilterEnabled: model.privacyFilterEnabled,
                        isLocked: model.isListening,
                        onThresholdChange: model.setConfidenceThreshold,
                        onPrivacyChange: model.setPrivacyFilterEnabled
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .fieldPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FieldStyle.paper, for: .navigationBar)
        }
    }
}

private struct ListenControl: View {
    var isListening: Bool
    var status: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(isListening ? FieldStyle.leaf.opacity(0.14) : FieldStyle.paperRecessed)
                        .frame(width: 166, height: 166)
                    Circle()
                        .strokeBorder(FieldStyle.paperRaised, lineWidth: 10)
                        .frame(width: 144, height: 144)
                    Circle()
                        .stroke(isListening ? FieldStyle.leaf : FieldStyle.moss, lineWidth: 1.5)
                        .frame(width: 126, height: 126)
                    Image(systemName: isListening ? "stop.fill" : "waveform")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(isListening ? FieldStyle.leaf : FieldStyle.moss)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Stop listening" : "Start listening")

            Text(status)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(FieldStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
                FieldSectionLabel("field controls", systemImage: "slider.horizontal.3")
                Spacer()
                if isLocked {
                    FieldPill("locked", systemImage: "lock.fill", color: FieldStyle.clay)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FieldStyle.ink)
                    Spacer()
                    Text("\(Int(confidenceThreshold * 100))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FieldStyle.inkMuted)
                }

                Slider(
                    value: Binding(
                        get: { Double(confidenceThreshold) },
                        set: { onThresholdChange(Float($0)) }
                    ),
                    in: 0.30...0.95,
                    step: 0.05
                )
                .tint(FieldStyle.moss)
                .disabled(isLocked)
            }

            Toggle(isOn: Binding(get: { privacyFilterEnabled }, set: onPrivacyChange)) {
                Label("Privacy filtering", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FieldStyle.ink)
            }
            .tint(FieldStyle.moss)
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
                FieldSectionLabel("diagnostics", systemImage: "gauge.with.dots.needle.bottom.50percent")
                Spacer()
                if diagnostics.privacySuppressed {
                    FieldPill("private", systemImage: "hand.raised.fill", color: FieldStyle.clay)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                FieldMetric(title: "Windows", value: "\(diagnostics.windowsProcessed)")
                FieldMetric(title: "Level", value: "\(Int(diagnostics.audioLevel * 100))%")
                FieldMetric(title: "Latency", value: latencyText)
                FieldMetric(title: "Range", value: rangeText)
            }

            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .foregroundStyle(FieldStyle.moss)
                Text(audioInputText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FieldStyle.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
        }
        .fieldPanel()
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
}

private struct LiveCandidatePanel: View {
    var diagnostics: DetectionDiagnostics
    var threshold: Float
    var isListening: Bool

    @State private var trail: [CandidateTrace] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                FieldSectionLabel("live candidate", systemImage: "ear")
                Spacer()
                FieldPill(candidateState.title, systemImage: candidateState.systemImage, color: candidateState.color)
            }

            HStack(alignment: .center, spacing: 16) {
                ConfidenceRing(
                    confidence: displayedConfidence,
                    color: candidateState.color,
                    isListening: isListening
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(displayedName)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(FieldStyle.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(candidateDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FieldStyle.inkMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if let rawCandidateDetail {
                        Text(rawCandidateDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(FieldStyle.inkFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            if !trail.isEmpty {
                CandidateTrail(trail: trail)
            }
        }
        .fieldPanel(inset: 18)
        .onChange(of: diagnostics) { _, newDiagnostics in
            appendTrace(from: newDiagnostics)
        }
    }

    private var displayedName: String {
        diagnostics.acceptedCandidateName ?? diagnostics.topCandidateName ?? idleName
    }

    private var idleName: String {
        isListening ? "Listening..." : "Awaiting first window"
    }

    private var displayedConfidence: Float? {
        diagnostics.acceptedCandidateConfidence ?? diagnostics.topCandidateConfidence
    }

    private var candidateState: CandidateState {
        if diagnostics.privacySuppressed {
            return .privateWindow
        }
        if diagnostics.acceptedCandidateName != nil {
            guard let confidence = diagnostics.acceptedCandidateConfidence else {
                return .loggable
            }
            if confidence >= 0.90 {
                return .strong
            }
            if confidence >= 0.75 {
                return .likely
            }
            return .loggable
        }
        guard let confidence = diagnostics.topCandidateConfidence,
              diagnostics.topCandidateName != nil else {
            return isListening ? .listening : .idle
        }
        if confidence < threshold {
            return .belowThreshold
        }
        if diagnostics.rangeFilterActive {
            return .outsideRange
        }
        return .considering
    }

    private var candidateDetail: String {
        switch candidateState {
        case .strong:
            return "Strong match. This candidate can be logged."
        case .likely:
            return "Likely match. This candidate can be logged."
        case .loggable:
            return "Above threshold and eligible for the field log."
        case .belowThreshold:
            return "The model hears a possibility, but it is below your \(Int(threshold * 100))% threshold."
        case .outsideRange:
            return "Strong enough, but filtered out by the local range model."
        case .privateWindow:
            return "Privacy filtering is suppressing this window."
        case .considering:
            return "The model is considering this sound."
        case .listening:
            return "Waiting for the first three-second audio window."
        case .idle:
            return "Tap Listen to begin local classification."
        }
    }

    private var rawCandidateDetail: String? {
        guard let acceptedName = diagnostics.acceptedCandidateName,
              let rawName = diagnostics.topCandidateName,
              rawName != acceptedName else {
            return nil
        }

        let confidence = diagnostics.topCandidateConfidence.map { " \(Int($0 * 100))%" } ?? ""
        return "Raw top: \(rawName)\(confidence)"
    }

    private func appendTrace(from diagnostics: DetectionDiagnostics) {
        guard diagnostics.windowsProcessed > 0,
              let name = diagnostics.topCandidateName,
              let confidence = diagnostics.topCandidateConfidence else {
            return
        }

        let trace = CandidateTrace(
            id: diagnostics.windowsProcessed,
            name: name,
            confidence: confidence,
            state: candidateState
        )
        guard trail.last?.id != trace.id else {
            return
        }

        trail.insert(trace, at: 0)
        trail = Array(trail.prefix(7))
    }
}

private struct ConfidenceRing: View {
    var confidence: Float?
    var color: Color
    var isListening: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(FieldStyle.paperRecessed)
            Circle()
                .stroke(FieldStyle.rule, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(confidence ?? 0))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(color.opacity(isListening ? 0.18 : 0.08), lineWidth: isListening ? 18 : 10)
                .scaleEffect(isListening ? 1.04 : 1)
            Text(confidenceText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(FieldStyle.ink)
        }
        .frame(width: 88, height: 88)
        .animation(.easeInOut(duration: 0.25), value: confidence)
    }

    private var confidenceText: String {
        guard let confidence else {
            return "--"
        }
        return "\(Int(confidence * 100))%"
    }
}

private struct CandidateTrail: View {
    var trail: [CandidateTrace]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("recent guesses")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(FieldStyle.inkFaint)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trail.enumerated()), id: \.element.id) { index, trace in
                        CandidateChip(trace: trace)
                            .opacity(max(0.38, 1 - Double(index) * 0.11))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct CandidateChip: View {
    var trace: CandidateTrace

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage = trace.state.systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(trace.name)
                .lineLimit(1)
            Text("\(Int(trace.confidence * 100))%")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(trace.state.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trace.state.color.opacity(0.10), in: Capsule())
    }
}

private struct CandidateTrace: Identifiable, Equatable {
    var id: Int
    var name: String
    var confidence: Float
    var state: CandidateState
}

private enum CandidateState: Equatable {
    case strong
    case likely
    case loggable
    case belowThreshold
    case outsideRange
    case privateWindow
    case considering
    case listening
    case idle

    var title: String {
        switch self {
        case .strong:
            return "strong"
        case .likely:
            return "likely"
        case .loggable:
            return "loggable"
        case .belowThreshold:
            return "below threshold"
        case .outsideRange:
            return "outside range"
        case .privateWindow:
            return "private"
        case .considering:
            return "considering"
        case .listening:
            return "listening"
        case .idle:
            return "idle"
        }
    }

    var systemImage: String? {
        switch self {
        case .strong, .likely, .loggable:
            return "checkmark"
        case .belowThreshold:
            return "waveform.path.ecg"
        case .outsideRange:
            return "location.slash"
        case .privateWindow:
            return "hand.raised.fill"
        case .considering:
            return "ear"
        case .listening:
            return "waveform"
        case .idle:
            return nil
        }
    }

    var color: Color {
        switch self {
        case .strong:
            return FieldStyle.leaf
        case .likely, .loggable:
            return FieldStyle.moss
        case .belowThreshold:
            return FieldStyle.clay
        case .outsideRange:
            return FieldStyle.sky
        case .privateWindow:
            return FieldStyle.clay
        case .considering, .listening, .idle:
            return FieldStyle.inkFaint
        }
    }
}

private struct RecentHitsList: View {
    var detections: [FieldDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldSectionLabel("recent hits", systemImage: "clock")

            if detections.isEmpty {
                ContentUnavailableView("No detections yet", systemImage: "waveform.badge.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .foregroundStyle(FieldStyle.inkFaint)
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
