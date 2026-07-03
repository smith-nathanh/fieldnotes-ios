import Combine
import CoreLocation
import Foundation
import FieldnotesCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var detections: [FieldDetection] = []
    @Published private(set) var summaries: [SpeciesSummary] = []
    @Published private(set) var recentHits: [FieldDetection] = []
    @Published private(set) var isListening = false
    @Published private(set) var status = "Ready"
    @Published private(set) var diagnostics = DetectionDiagnostics.empty
    @Published private(set) var privacyFilterEnabled: Bool
    @Published private(set) var confidenceThreshold: Float

    private var store = DetectionStore()
    private let repository: DetectionRepository
    private let injectedDetector: DetectionEngine?
    private let clipWriter = AudioClipWriter()
    private let locationService = LocationService()
    private var listeningTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let privacyFilterEnabledKey = "privacyFilterEnabled"
    private let confidenceThresholdKey = "confidenceThreshold"
    private let defaultSettings = DetectionSettings()

    init(
        repository: DetectionRepository? = nil,
        detector: DetectionEngine? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository ?? DetectionRepository()
        self.injectedDetector = detector
        self.defaults = defaults
        self.privacyFilterEnabled = defaults.bool(forKey: privacyFilterEnabledKey)
        if defaults.object(forKey: confidenceThresholdKey) == nil {
            self.confidenceThreshold = defaultSettings.confidenceThreshold
        } else {
            self.confidenceThreshold = Self.clampedConfidenceThreshold(defaults.float(forKey: confidenceThresholdKey))
        }
    }

    func load() async {
        do {
            detections = try await repository.load()
            store = DetectionStore(detections: detections)
            refreshDerivedState()
        } catch {
            status = "Could not load field log"
        }
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening else {
            return
        }
        isListening = true
        status = "Listening"
        locationService.start()

        let detector = injectedDetector ?? LiveDetectionEngine(settings: detectionSettings())
        listeningTask = Task { [detector] in
            do {
                for try await event in detector.events() {
                    if Task.isCancelled {
                        break
                    }
                    switch event {
                    case .detection(let detection):
                        await record(detection)
                    case .diagnostics(let diagnostics):
                        await MainActor.run {
                            self.diagnostics = diagnostics
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.status = error.localizedDescription
                    self.isListening = false
                }
            }
        }
    }

    func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
        isListening = false
        status = "Paused"
        locationService.stop()
    }

    func setPrivacyFilterEnabled(_ enabled: Bool) {
        guard !isListening else {
            return
        }
        privacyFilterEnabled = enabled
        defaults.set(enabled, forKey: privacyFilterEnabledKey)
    }

    func setConfidenceThreshold(_ threshold: Float) {
        guard !isListening else {
            return
        }
        let clampedThreshold = Self.clampedConfidenceThreshold(threshold)
        confidenceThreshold = clampedThreshold
        defaults.set(clampedThreshold, forKey: confidenceThresholdKey)
    }

    func detections(for summary: SpeciesSummary) -> [FieldDetection] {
        detections
            .filter { $0.scientificName == summary.scientificName }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    func addPhotoPredictionToLog(_ prediction: BioCAPPhotoPrediction) async {
        let detectedAt = Date()
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: detectedAt)
        let detection = FieldDetection(
            scientificName: prediction.scientificName,
            commonName: prediction.commonName,
            taxon: Taxon(rawValue: prediction.taxon) ?? .unknown,
            source: .photo,
            confidence: prediction.score,
            detectedAt: detectedAt,
            week: week
        )
        await record(detection)
    }

    private func record(_ detection: FieldDetection) async {
        let detection = detectionWithCurrentLocation(detection)
        let decision = store.decision(for: detection)
        let replacedClipURL: URL?
        if case .insertReplacingClip(let existingID) = decision {
            replacedClipURL = store.detections.first { $0.id == existingID }?.clipURL
        } else {
            replacedClipURL = nil
        }

        _ = store.record(detection)

        if case .insertWithoutClip = decision {
            clipWriter.deleteClip(at: detection.clipURL)
        }
        if case .insertReplacingClip = decision {
            clipWriter.deleteClip(at: replacedClipURL)
        }

        detections = store.detections.sorted { $0.detectedAt > $1.detectedAt }
        refreshDerivedState()
        status = "\(detection.commonName) \(scoreText(for: detection))"

        do {
            try await repository.save(store.detections)
        } catch {
            status = "Could not save field log"
        }
    }

    private func refreshDerivedState() {
        summaries = store.summaries()
        recentHits = detections.prefix(8).map { $0 }
    }

    private func detectionSettings() -> DetectionSettings {
        let location = locationService.currentLocation
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: Date())

        return DetectionSettings(
            confidenceThreshold: confidenceThreshold,
            privacyFilterEnabled: privacyFilterEnabled,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            week: week
        )
    }

    private func detectionWithCurrentLocation(_ detection: FieldDetection) -> FieldDetection {
        var detection = detection
        detection.week = Calendar(identifier: .iso8601).component(.weekOfYear, from: detection.detectedAt)

        guard let location = locationService.currentLocation else {
            return detection
        }

        detection.latitude = location.coordinate.latitude
        detection.longitude = location.coordinate.longitude
        return detection
    }

    private static func clampedConfidenceThreshold(_ threshold: Float) -> Float {
        min(0.95, max(0.30, threshold))
    }

    private func scoreText(for detection: FieldDetection) -> String {
        switch detection.source {
        case .audio:
            return "\(Int(detection.confidence * 100))%"
        case .photo:
            return "\(detection.confidence.formatted(.number.precision(.fractionLength(3)))) sim"
        }
    }
}
