import FieldnotesCore
import SwiftUI

struct ListenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                    TripStatusBanner(
                        trip: model.activeTrip,
                        locationTaggingEnabled: model.locationTaggingEnabled,
                        onStart: model.startTrip,
                        onEnd: model.endActiveTrip
                    )

                    ListenControl(
                        isListening: model.isListening,
                        hasSession: model.elapsedListening > 0,
                        status: model.status,
                        primaryAction: model.isListening
                            ? model.pauseListeningSession
                            : model.elapsedListening > 0
                                ? model.resumeListeningSession
                                : model.startNewListeningSession,
                        newSessionAction: model.startNewListeningSession
                    )

                    if model.isListening || model.elapsedListening > 0 {
                        SessionSummary(
                            elapsed: model.elapsedListening,
                            speciesCount: model.sessionSpeciesCount,
                            detectionCount: model.sessionDetectionCount,
                            isLive: model.isListening
                        )
                    }

                    AlmanacSection("Live Candidate") {
                        LiveCandidatePanel(
                            diagnostics: model.diagnostics,
                            threshold: model.confidenceThreshold,
                            isListening: model.isListening
                        )
                    }

                    AlmanacSection("Recent Hits") {
                        RecentHitsList(detections: model.recentHits)
                    }

                    AlmanacSection("Field Controls") {
                        FieldControls(
                            confidenceThreshold: model.confidenceThreshold,
                            privacyFilterEnabled: model.privacyFilterEnabled,
                            locationTaggingEnabled: model.locationTaggingEnabled,
                            isLocked: model.isListening,
                            onThresholdChange: model.setConfidenceThreshold,
                            onPrivacyChange: model.setPrivacyFilterEnabled,
                            onLocationTaggingChange: model.setLocationTaggingEnabled
                        )
                    } trailing: {
                        if model.isListening {
                            TagChip(text: "locked", textColor: .rust, fill: Color.rust.opacity(0.12), borderColor: nil)
                        }
                    }
                    }
                    .frame(
                        width: max(0, geometry.size.width - AlmanacLayout.screenPadding * 2),
                        alignment: .leading
                    )
                    .padding(.horizontal, AlmanacLayout.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, .tabBarClearance)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
            .almanacBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ListenControl: View {
    var isListening: Bool
    var hasSession: Bool
    var status: String
    var primaryAction: () -> Void
    var newSessionAction: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Button(action: primaryAction) {
                ZStack {
                    Circle()
                        .fill(Color.paper)
                        .frame(width: 176, height: 176)
                    Circle()
                        .stroke(Color.ink, lineWidth: 2)
                        .frame(width: 170, height: 170)
                    if isListening {
                        Circle()
                            .stroke(Color.rust, lineWidth: 12)
                            .frame(width: 170, height: 170)
                            .opacity(pulse ? 0.42 : 0.12)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    }
                    VStack(spacing: 10) {
                        Image(systemName: isListening ? "pause.fill" : "waveform")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.rust)
                        Text(primaryTitle)
                            .font(.serif(16, .semibold))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryTitle)
            .onAppear { pulse = isListening }
            .onChange(of: isListening) { _, listening in
                pulse = listening
            }

            Text(guidance)
                .font(.serif(15))
                .foregroundStyle(Color.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if hasSession && !isListening {
                Button("Start New Session", action: newSessionAction)
                    .buttonStyle(AlmanacSecondaryButton())
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        if isListening { return "Pause Listening" }
        if hasSession { return "Resume Listening" }
        return "Start Listening"
    }

    private var guidance: String {
        if !["Ready", "Listening", "Paused"].contains(status) {
            return status
        }
        if isListening {
            return "Listening for nearby wildlife. Pause whenever you need to."
        }
        if hasSession {
            return "Resume this session or start a new one with fresh totals."
        }
        return "Tap to identify birds, frogs, insects, and other wildlife."
    }
}

private struct SessionSummary: View {
    var elapsed: TimeInterval
    var speciesCount: Int
    var detectionCount: Int
    var isLive: Bool

    var body: some View {
        AlmanacSection("This Session") {
            HStack(alignment: .top, spacing: 16) {
                MetricBlock(title: "Duration", value: durationText, valueColor: isLive ? .rust : .ink)
                MetricBlock(title: "Species", value: "\(speciesCount)")
                MetricBlock(title: "Detections", value: "\(detectionCount)")
            }
        } trailing: {
            if isLive {
                Circle()
                    .fill(Color.rust)
                    .frame(width: 8, height: 8)
            } else {
                TagChip(text: "paused", textColor: .inkSoft, fill: .paperCard, borderColor: .ink)
            }
        }
    }

    private var durationText: String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct FieldControls: View {
    var confidenceThreshold: Float
    var privacyFilterEnabled: Bool
    var locationTaggingEnabled: Bool
    var isLocked: Bool
    var onThresholdChange: (Float) -> Void
    var onPrivacyChange: (Bool) -> Void
    var onLocationTaggingChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                        .font(.serif(18))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text("\(Int(confidenceThreshold * 100))%")
                        .font(.serif(19, .semibold))
                        .foregroundStyle(Color.rust)
                }

                Slider(
                    value: Binding(
                        get: { Double(confidenceThreshold) },
                        set: { onThresholdChange(Float($0)) }
                    ),
                    in: 0.30...0.95,
                    step: 0.05
                )
                .tint(Color.rust)
                .disabled(isLocked)
            }

            Toggle(isOn: Binding(get: { privacyFilterEnabled }, set: onPrivacyChange)) {
                Text("Privacy filtering")
                    .font(.serif(18))
                    .foregroundStyle(Color.ink)
            }
            .tint(Color.rust)
            .disabled(isLocked)

            Toggle(isOn: Binding(get: { locationTaggingEnabled }, set: onLocationTaggingChange)) {
                Text("Location tagging")
                    .font(.serif(18))
                    .foregroundStyle(Color.ink)
            }
            .tint(Color.rust)
            .disabled(isLocked)
        }
    }
}

private struct LiveCandidatePanel: View {
    var diagnostics: DetectionDiagnostics
    var threshold: Float
    var isListening: Bool

    @State private var trail: [CandidateTrace] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ConfidenceRing(
                    confidence: displayedConfidence,
                    isListening: isListening
                )

                VStack(alignment: .leading, spacing: 7) {
                    TagChip(
                        text: candidateState.title,
                        textColor: candidateState.color,
                        fill: .paperCard,
                        borderColor: .ink
                    )

                    Text(displayedName)
                        .font(.serif(22, .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(candidateDetail)
                        .font(.serif(14))
                        .foregroundStyle(Color.inkSoft)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let rawCandidateDetail {
                        Text(rawCandidateDetail)
                            .font(.mono(10, .regular))
                            .tracking(.tracking(0.04, at: 10))
                            .foregroundStyle(Color.monoLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !trail.isEmpty {
                CandidateTrail(trail: trail)
            }
        }
        .onChange(of: diagnostics) { _, newDiagnostics in
            appendTrace(from: newDiagnostics)
        }
    }

    private var displayedName: String {
        diagnostics.acceptedCandidateName ?? diagnostics.topCandidateName ?? idleName
    }

    private var idleName: String {
        isListening ? "Listening..." : "Waiting to listen"
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
            return "Listening for a clear wildlife sound."
        case .idle:
            return "Live suggestions will appear here while Fieldnotes listens."
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
    var isListening: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.paperCard)
            Circle()
                .stroke(Color.hairline, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(confidence ?? 0))
                .stroke(Color.rust, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(confidenceText)
                .font(.serif(20, .semibold))
                .foregroundStyle(Color.ink)
        }
        .frame(width: 88, height: 88)
        .overlay(Circle().stroke(Color.ink, lineWidth: 1))
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
            Text("recent guesses".uppercased())
                .font(.mono(9, .regular))
                .tracking(.tracking(0.10, at: 9))
                .foregroundStyle(Color.monoLabel)

            HStack(spacing: 8) {
                ForEach(Array(trail.prefix(3).enumerated()), id: \.element.id) { index, trace in
                    CandidateChip(trace: trace)
                        .opacity(max(0.4, 1 - Double(index) * 0.11))
                }
            }
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
}

private struct CandidateChip: View {
    var trace: CandidateTrace

    var body: some View {
        HStack(spacing: 6) {
            Text(trace.name)
                .font(.serif(13))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Text("\(Int(trace.confidence * 100))%")
                .font(.mono(10, .medium))
                .foregroundStyle(trace.state.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.paperCard))
        .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
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
            return "ready"
        }
    }

    var color: Color {
        switch self {
        case .strong, .likely, .loggable:
            return .rust
        case .belowThreshold, .considering, .listening:
            return .inkSoft
        case .outsideRange, .privateWindow:
            return .olive
        case .idle:
            return .inkFaint
        }
    }
}

private struct RecentHitsList: View {
    var detections: [FieldDetection]

    var body: some View {
        if detections.isEmpty {
            AlmanacEmpty("No detections yet", message: "accepted hits appear here")
        } else {
            VStack(spacing: 0) {
                ForEach(detections) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
    }
}
