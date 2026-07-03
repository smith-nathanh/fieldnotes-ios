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
    @Published private(set) var locationTaggingEnabled: Bool
    @Published private(set) var elapsedListening: TimeInterval = 0
    @Published private(set) var sessionSpeciesCount = 0
    @Published private(set) var sessionDetectionCount = 0

    private var store = DetectionStore()
    private let repository: DetectionRepository
    private let injectedDetector: DetectionEngine?
    private let clipWriter = AudioClipWriter()
    private let locationService = LocationService()
    private var listeningTask: Task<Void, Never>?
    private var sessionStartedAt: Date?
    private var sessionScientificNames: Set<String> = []
    private var sessionTimer: Timer?
    private var sessionOutingId: UUID?
    private let defaults: UserDefaults
    private let privacyFilterEnabledKey = "privacyFilterEnabled"
    private let confidenceThresholdKey = "confidenceThreshold"
    private let locationTaggingEnabledKey = "locationTaggingEnabled"
    private let defaultSettings = DetectionSettings()

    private static let audioModelVersion = "BirdNET_GLOBAL_6K_V2.4"
    private static let photoModelVersion = "hf-hub:imageomics/biocap"

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
        // Location tagging defaults on, preserving prior behavior; users can
        // opt out to stop attaching coarse GPS to detections.
        if defaults.object(forKey: locationTaggingEnabledKey) == nil {
            self.locationTaggingEnabled = true
        } else {
            self.locationTaggingEnabled = defaults.bool(forKey: locationTaggingEnabledKey)
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
        startSessionTracking()

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
                    self.stopSessionTracking()
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
        stopSessionTracking()
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

    func setLocationTaggingEnabled(_ enabled: Bool) {
        guard !isListening else {
            return
        }
        locationTaggingEnabled = enabled
        defaults.set(enabled, forKey: locationTaggingEnabledKey)
    }

    func detections(for summary: SpeciesSummary) -> [FieldDetection] {
        detections
            .filter { $0.scientificName == summary.scientificName }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    var outings: [Outing] {
        store.outings()
    }

    func detections(for outing: Outing) -> [FieldDetection] {
        detections
            .filter { $0.outingId == outing.id }
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
        let detection = enrichedDetection(detection)
        let decision = store.decision(for: detection)

        // Determine which clip to discard, and whether the log actually changed,
        // before mutating the store.
        let clipToDelete: URL?
        let didLog: Bool
        switch decision {
        case .insert:
            clipToDelete = nil
            didLog = true
        case .replace(let existingID):
            // Keep the new (stronger) clip; drop the one being replaced.
            clipToDelete = store.detections.first { $0.id == existingID }?.clipURL
            didLog = true
        case .skip:
            // Discard this call entirely, including its freshly written clip.
            clipToDelete = detection.clipURL
            didLog = false
        }

        _ = store.record(detection)
        if let clipToDelete {
            clipWriter.deleteClip(at: clipToDelete)
        }

        // A skipped call within the cooldown window changes nothing — leave the
        // log, session tally, and status untouched.
        guard didLog else {
            return
        }

        detections = store.detections.sorted { $0.detectedAt > $1.detectedAt }
        refreshDerivedState()
        if case .insert = decision {
            noteSessionDetection(detection)
        }
        status = "\(detection.commonName) \(scoreText(for: detection))"

        do {
            try await repository.save(store.detections)
        } catch {
            status = "Could not save field log"
        }
    }

    private func refreshDerivedState() {
        summaries = store.summaries()
        // Recent Hits on the Listen screen are audio-only; photo captures come
        // from the Photo tab and belong in the Log/Stats, not the listen feed.
        recentHits = Array(detections.filter { $0.source == .audio }.prefix(8))
    }

    // MARK: - Listen session tracking

    private func startSessionTracking() {
        sessionStartedAt = Date()
        sessionOutingId = UUID()
        elapsedListening = 0
        sessionDetectionCount = 0
        sessionSpeciesCount = 0
        sessionScientificNames.removeAll()
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSession() }
        }
    }

    private func tickSession() {
        guard let sessionStartedAt else {
            return
        }
        elapsedListening = Date().timeIntervalSince(sessionStartedAt)
    }

    private func stopSessionTracking() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        if let sessionStartedAt {
            elapsedListening = Date().timeIntervalSince(sessionStartedAt)
        }
        // Keep the elapsed time and tallies so the last session's summary
        // stays on screen until the next session starts.
        sessionStartedAt = nil
        sessionOutingId = nil
    }

    private func noteSessionDetection(_ detection: FieldDetection) {
        guard sessionStartedAt != nil, detection.source == .audio else {
            return
        }
        sessionDetectionCount += 1
        sessionScientificNames.insert(detection.scientificName)
        sessionSpeciesCount = sessionScientificNames.count
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

    /// Stamps the metadata the app should capture on every detection (§9.1):
    /// coarse location + accuracy, model version, outing grouping, and the
    /// first-of-species flag. Location is only attached when tagging is enabled.
    private func enrichedDetection(_ detection: FieldDetection) -> FieldDetection {
        var detection = detectionWithCurrentLocation(detection)

        if detection.modelVersion == nil {
            detection.modelVersion = detection.source == .audio
                ? Self.audioModelVersion
                : Self.photoModelVersion
        }

        if detection.source == .audio, let sessionOutingId {
            detection.outingId = sessionOutingId
        }

        // Computed before the store records it, so it reflects prior history.
        detection.isFirstOfSpecies = !store.detections.contains {
            $0.scientificName == detection.scientificName
        }

        return detection
    }

    private func detectionWithCurrentLocation(_ detection: FieldDetection) -> FieldDetection {
        var detection = detection
        detection.week = Calendar(identifier: .iso8601).component(.weekOfYear, from: detection.detectedAt)

        guard locationTaggingEnabled, let location = locationService.currentLocation else {
            detection.latitude = nil
            detection.longitude = nil
            detection.locationAccuracy = nil
            return detection
        }

        detection.latitude = location.coordinate.latitude
        detection.longitude = location.coordinate.longitude
        detection.locationAccuracy = location.horizontalAccuracy
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
